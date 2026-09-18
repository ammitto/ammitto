# frozen_string_literal: true

require 'digest'
require 'yaml'
require_relative '../../errors/base_error'
require_relative 'filename_collision_error'

module Ammitto
  module Cmd
    module Fetch
      module CollisionAndCollapseGuard
        # @return [Float] share of the previous harvest a run must reach
        #
        # Half. Sanctions lists move by tens of records between runs, so a
        # drop through this is a parser that stopped matching, not a wave of
        # delistings. It is the ratio harmonize already uses for its own
        # unique-identifier gate.
        COLLAPSE_RATIO = 0.5

        private

        # Write each item to its own file, refusing to overwrite one record
        # with a different one.
        #
        # File.write truncates, so two items whose filenames collide used to
        # leave one record on disk and no trace of the other — the run still
        # reported success and the missing designee surfaced nowhere. A
        # repeated filename carrying byte-identical content is a duplicated
        # upstream row and collapses harmlessly; a repeated filename
        # carrying different content is data loss and fails the source.
        #
        # Collisions are resolved before anything is written, so a run that
        # would have discarded a record leaves the destination untouched
        # rather than half-replaced. Only filenames claimed more than once
        # are rendered twice, so the common path costs one pass.
        #
        # @param source [Symbol] source code
        # @param items [Array] items to write
        # @param output_dir [String] output directory
        # @return [Hash{String => Array}] filename => claimants
        # @raise [FilenameCollisionError] when two different records claim
        #   one filename
        # @raise [Ammitto::ParseError] when the harvest collapsed against the
        #   previous one, or the index recording it cannot be read
        def write_items(source, items, output_dir)
          claims = items.group_by { |item| filename_for_item(source, item) }
          collisions = detect_collisions(claims)

          raise FilenameCollisionError.new(source, collisions) unless collisions.empty?

          # Checked on the grouping rather than on `items`, and before the
          # first write, because that is where a collapse becomes visible.
          # Canada parsed 5690 items on the day it broke, exactly as many as
          # the day before; what changed is that they all claimed one
          # filename.
          refuse_collapse(source, claims.size, output_dir)

          claims.each_with_index do |(filename, claimants), index|
            File.write(File.join(output_dir, filename),
                       claimants.first.to_yaml)
            report_progress(source, index + 1)
          end

          claims
        end

        # Refuse a harvest that produced a small fraction of the last one.
        #
        # Canada went from 5690 records to 1 on 2026-08-25, when the source
        # renamed every element in its XML to a bilingual form. Every record
        # still parsed and every field in every record came back nil, so all
        # 5690 claimed one empty filename, and `detect_collisions` — which
        # forgives a repeated filename whose claimants are byte-identical —
        # let them through as a single duplicated row. Three runs reported
        # success.
        #
        # That exact shape is now caught earlier: `filename_for_item` refuses
        # a record with no usable identifier at all. What it cannot see is
        # the partial case, where enough of the document still parses to
        # produce identifiers but most of it no longer matches — a renamed
        # container, a namespace change on one branch, a page of results
        # silently truncated. Then the run writes real records, just far
        # fewer of them, and every existing gate passes: they are not zero,
        # they are not blank, and nothing compares them to yesterday.
        #
        # @param source [Symbol] source code
        # @param count [Integer] files this run is about to write
        # @param output_dir [String] directory holding the previous index
        # @raise [Ammitto::ParseError] when the drop is too large to be real
        # @return [void]
        def refuse_collapse(source, count, output_dir)
          return if options[:allow_shrink]

          previous = previous_harvest_count(source, output_dir)
          return if previous.nil?
          return if count >= previous * COLLAPSE_RATIO

          raise Ammitto::ParseError, collapse_message(source, count, previous)
        end

        # The count the last harvest into this directory recorded, or nil
        # when there has not been one.
        #
        # Only absence returns nil. `_index.yaml` is missing on a first
        # harvest and after a directory is cleared by hand, and neither is a
        # reason to refuse. An index that is present and cannot be read is:
        # treating that as "no previous harvest" would let a corrupt file
        # switch this gate off without saying so, which is the shape of
        # failure the gate exists to catch.
        #
        # @param source [Symbol] source code
        # @param output_dir [String] directory to read the index from
        # @return [Integer, nil] the previous count, or nil if none is recorded
        # @raise [Ammitto::ParseError] when an index exists but yields no count
        def previous_harvest_count(source, output_dir)
          path = File.join(output_dir, '_index.yaml')
          return nil unless File.exist?(path)

          count = index_count(path)
          return count if count.is_a?(Integer) && !count.negative?

          raise Ammitto::ParseError, unreadable_index_message(source, path)
        end

        # @param path [String] the index file
        # @return [Object, nil] whatever `count` holds, or nil if unreadable
        def index_count(path)
          document = YAML.safe_load_file(path)
          # A document that parses but is not a mapping — a bare list, a
          # number, `false` — has no key to read. Checked rather than
          # rescued: rescuing the TypeError it would raise would also
          # swallow a programming error here.
          return nil unless document.is_a?(Hash)

          document['count']
        rescue Psych::Exception, SystemCallError, IOError
          nil
        end

        # @param source [Symbol] source code
        # @param path [String] the index file
        # @return [String] the refusal
        def unreadable_index_message(source, path)
          "#{source}: #{path} exists but no record count could be read " \
            'from it. That file is what the collapse check compares this ' \
            'harvest against, so continuing would publish without the ' \
            'check rather than with it. Repair or remove the file, or ' \
            'pass --allow-shrink to harvest without comparing.'
        end

        # @param source [Symbol] source code
        # @param count [Integer] files this run produced
        # @param previous [Integer] files the last run produced
        # @return [String] the refusal
        def collapse_message(source, count, previous)
          "#{source}: this harvest produced #{count} record(s) where the " \
            "last one produced #{previous}. A sanctions list does not lose " \
            'that share of its records in one run, so the source format ' \
            'has probably changed and the parser is matching less of it. ' \
            'Refusing rather than publishing the remainder as though it ' \
            'were the whole list. Pass --allow-shrink if the drop is real.'
        end

        # Find filenames claimed by records that are not byte-identical.
        #
        # A repeated filename carrying identical content is a duplicated
        # upstream row: writing it once loses nothing. Differing content is
        # data loss, because File.write truncates.
        #
        # @param claims [Hash{String => Array}] filename => claimants
        # @return [Hash{String => Array}] filename => records that would be
        #   discarded
        def detect_collisions(claims)
          claims.each_with_object({}) do |(filename, claimants), found|
            next if claimants.size == 1

            distinct = claimants.uniq do |item|
              Digest::SHA256.hexdigest(item.to_yaml)
            end
            next if distinct.size == 1

            found[filename] = distinct.drop(1)
          end
        end

        # Report progress every hundredth file actually written
        # @param source [Symbol] source code
        # @param count [Integer] files written so far
        # @return [void]
        def report_progress(source, count)
          return unless options[:verbose] && (count % 100).zero?

          puts "[#{source}] Saved #{count} files..."
        end
      end
    end
  end
end
