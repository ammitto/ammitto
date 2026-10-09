# frozen_string_literal: true

require 'yaml'
require_relative 'item_mapper'
require_relative '../../utils/presence'

module Ammitto
  module Cmd
    module Fetch
      # Remove the files of records the source no longer lists.
      #
      # Fetch is a transcription of the current list, and harmonize reads
      # every file in the directory. A record the source dropped would
      # otherwise keep its file and stay published as active. The data
      # repository's git history records the removal, so nothing is kept
      # here to mark it.
      #
      # Deleting is the one thing fetch does that a later run cannot undo,
      # so every doubt leaves the files where they are. A file is a
      # candidate when the previous index names this source and either
      # records the file as its own, or the source's filenames carry a
      # prefix, the file carries it and its content has the shape of this
      # source's records. A prefix alone proves nothing, because the files
      # hold no source field and a directory can hold another source's
      # file under a name that happens to match: a file under the prefix
      # that is not shaped like this source's record is never adopted. The
      # unprefixed sources (uk, eu, un, us) have no name to narrow the
      # directory, and their record classes share keys (addresses,
      # entity_type, first_name), so a file made only of shared keys would
      # pass the shape test of several: for them the file must also carry
      # the key the record's identifier reads, which a written record
      # always has and a stray file of shared keys does not.
      module StaleRecordPruner
        # The largest share of the previous harvest one run may remove.
        # Delistings arrive a few at a time; a larger drop is more likely a
        # parser that matched only part of the document, which the 50%
        # collapse guard lets through. Above this the files stay and the
        # run says why; --allow-shrink accepts the drop. One removal is
        # always within the limit, or a source small enough for 5% to round
        # to nothing could never drop a record.
        PRUNE_CEILING = 0.05

        # The key each unprefixed source's #identifier reads. No two of
        # these sources write the same one.
        IDENTITY_KEYS = {
          uk: 'unique_id', eu: 'eu_reference_number',
          un: 'reference_number', us: 'uid'
        }.freeze

        # The list-class attributes that lead to the records its #items
        # returns, which fetch writes as files. Most are record collections;
        # UN wraps its individual/entity collections, and a list can carry
        # collections that are not records (ch has programs beside its
        # targets), so the attributes are named, not discovered.
        ITEM_ATTRIBUTES = {
          uk: %i[designations], eu: %i[sanction_entities],
          un: %i[individuals entities], us: %i[entries],
          wb: %i[firms], au: %i[individuals organizations vessels generic_entities],
          ca: %i[records], ch: %i[targets], tr: %i[entities],
          nz: %i[individuals entities ships], eu_vessels: %i[vessels],
          un_vessels: %i[vessels]
        }.freeze

        private

        # Delete record files this source wrote before and this run did not.
        #
        # Called only after write_items returned, so a harvest it refused
        # never reaches here. An empty harvest is skipped explicitly: with
        # nothing written, every recorded file would look stale.
        #
        # @param source [Symbol] source code
        # @param written [Hash{String => Array}] filenames this run wrote
        # @param output_dir [String] output directory
        # @return [Array<String>] the filenames removed
        def prune_stale_records(source, written, output_dir)
          return [] unless options[:prune] && !written.empty?
          return [] if shared_output_dir?(source)

          previous = previous_index(source, output_dir)
          return [] unless previous

          stale = stale_records(source, written, output_dir, previous)
          return [] if prune_too_large?(source, stale.size, previous['count'])

          stale.select { |name| delete_if_still_owned(source, name, output_dir) }
        end

        # The scan above read the index once; an overlapping run may have
        # rewritten it since. Deleting on that stale reading could remove a
        # file another source now owns, so the index is read again at the
        # moment of deletion and the ownership test is repeated on it. This narrows the window and does not close
        # it: --prune does not lock the directory.
        #
        # @param source [Symbol] source code
        # @param name [String] file to remove
        # @param output_dir [String] output directory
        # @return [Boolean] true when this run removed the file; false when
        #   it was not owned any more or was already gone. Any other
        #   filesystem failure propagates: a requested prune that left the
        #   file in place must not report success.
        def delete_if_still_owned(source, name, output_dir)
          current = previous_index(source, output_dir)
          return false unless current && owned_name?(source, name, current, output_dir)

          File.delete(File.join(output_dir, name))
          true
        rescue Errno::ENOENT
          false
        end

        # Owned files a run left in place, which the next index must keep
        # naming. Without this a file the ceiling spared would drop out of
        # `files` and no later run, even with --allow-shrink, could remove
        # it. Called after prune_stale_records: a file it deleted no longer
        # exists and falls out of the candidates. Once a non-empty harvest
        # has been pruned, what remains here is what the ceiling spared.
        #
        # @param source [Symbol] source code
        # @param written [Hash{String => Array}] filenames this run wrote
        # @param output_dir [String] output directory
        # @return [Array<String>] sorted filenames still owned and present
        def retained_records(source, written, output_dir)
          return [] unless options[:prune]
          return [] if shared_output_dir_run?

          previous = previous_index(source, output_dir)
          return [] unless previous
          return carried_forward_files(previous) if written.empty?

          stale_records(source, written, output_dir, previous)
        end

        # A run that wrote nothing deleted nothing, so every file the
        # previous index owned is still owned. Recording an empty list
        # here would orphan them: no later run could prune them.
        # @param previous [Hash] the previous index of this source
        # @return [Array<String>] the previously recorded files, unchanged
        def carried_forward_files(previous)
          owned = previous['files']
          owned.is_a?(Array) ? owned.grep(String) : []
        end

        # One --output-dir given to several sources holds all their files
        # under one index, and the unprefixed sources cannot tell their
        # files from each other's.
        # @return [Boolean] whether one --output-dir serves several sources
        def shared_output_dir_run?
          options[:output_dir] && @sources.uniq.size > 1
        end

        # Silent test above plus the warning, for the run that skips.
        # @param source [Symbol] source code
        # @return [Boolean]
        def shared_output_dir?(source)
          return false unless shared_output_dir_run?

          warn "[#{source}] --prune skipped: #{@sources.uniq.size} sources " \
               "share --output-dir #{options[:output_dir]}"
          true
        end

        # This source's own index from the previous harvest, which shows the
        # directory is a harvest of the same list and not an arbitrary
        # directory passed as --output-dir.
        #
        # @param source [Symbol] source code
        # @param output_dir [String] output directory
        # @return [Hash, nil] the index, or nil when it is not this source's
        def previous_index(source, output_dir)
          path = File.join(output_dir, '_index.yaml')
          return nil unless File.file?(path)

          document = YAML.safe_load_file(path)
          document if document.is_a?(Hash) && document['source'] == source.to_s
        rescue Psych::Exception, SystemCallError, IOError
          nil
        end

        # @param source [Symbol] source code
        # @param written [Hash{String => Array}] filenames this run wrote
        # @param output_dir [String] output directory
        # @param previous [Hash] the previous index of this source
        # @return [Array<String>] sorted filenames
        def stale_records(source, written, output_dir, previous)
          prefix = ItemMapper::FILENAME_PREFIXES[source]
          return [] if prefix.nil?

          recorded = carried_forward_files(previous)
          candidates = recorded | prefixed_files(prefix, output_dir)
          candidates.select do |name|
            path = File.join(output_dir, name)
            name == File.basename(name) && !name.start_with?('.') && name.end_with?('.yaml') &&
              name != '_index.yaml' && name.start_with?(prefix) &&
              !written.key?(name) && File.file?(path) &&
              (!prefix.empty? || !File.symlink?(path)) &&
              (recorded.include?(name) || adoptable?(source, prefix, name, path))
          end.sort
        end

        # Whether the index, read at the moment of deletion, still lets this
        # source remove the file.
        # @param source [Symbol] source code
        # @param name [String] file to remove
        # @param current [Hash] the index of this source, read just now
        # @param output_dir [String] output directory
        # @return [Boolean]
        def owned_name?(source, name, current, output_dir)
          return true if carried_forward_files(current).include?(name)

          prefix = ItemMapper::FILENAME_PREFIXES[source]
          path = File.join(output_dir, name)
          (prefix.to_s.empty? ? !File.symlink?(path) : name.start_with?(prefix)) &&
            adoptable?(source, prefix.to_s, name, path)
        end

        # Whether a file no index records may be taken as this source's: it
        # must be shaped like its record, and an unprefixed source never
        # takes a file under another source's prefix, whose records can
        # carry the same keys (tr writes reference_number too). A file the
        # index records is this source's own whatever its name.
        # @param source [Symbol] source code
        # @param prefix [String] the source's filename prefix
        # @param name [String] filename
        # @param path [String] the file
        # @return [Boolean]
        def adoptable?(source, prefix, name, path)
          foreign = prefix.empty? && ItemMapper::FILENAME_PREFIXES.values.any? do |other|
            !other.empty? && name.start_with?(other)
          end
          !foreign && record_of_source?(source, path)
        end

        # Whether a file holds a record of this source, judged by its keys:
        # every top-level key must be one the source's record class writes.
        # A file that cannot be read, or is not a mapping, is not one. The
        # check is what keeps a shared prefix from handing one source
        # another's files.
        # @param source [Symbol] source code
        # @param path [String] the file
        # @return [Boolean]
        def record_of_source?(source, path)
          document = YAML.safe_load_file(path, permitted_classes: [Date, Time])
          return false unless document.is_a?(Hash) && !document.empty?
          return false unless identified?(source, document)

          record_keys(source).any? { |keys| (document.keys - keys).empty? }
        rescue Psych::Exception, SystemCallError, IOError
          false
        end

        # @param source [Symbol] source code
        # @param document [Hash] the file's top-level mapping
        # The identity attributes are strings, so anything else under the
        # key (false, a list, a mapping) is not a record's identity.
        # @return [Boolean] true when the source needs no identity key or
        #   the document carries a non-blank string under it, blank as
        #   Utils::Presence judges it, Unicode whitespace included
        def identified?(source, document)
          key = IDENTITY_KEYS[source]
          value = document[key] if key
          key.nil? || (value.is_a?(String) && Utils::Presence.present?(value))
        end

        # The YAML keys each record class of a source writes. A source
        # whose classes cannot be found yields none, so nothing is adopted.
        # @param source [Symbol] source code
        # @return [Array<Array<String>>] one key list per record class
        def record_keys(source)
          list = source_model_class_for(source)
          return [] unless list

          ITEM_ATTRIBUTES.fetch(source, []).filter_map do |name|
            attribute = list.attributes[name]
            record_class = if attribute&.collection?
                             attribute.type
                           elsif attribute&.type.respond_to?(:attributes)
                             attribute.type.attributes[:items]&.type
                           end
            next unless record_class.respond_to?(:mappings_for)

            record_class.mappings_for(:yaml).mappings.map { |mapping| mapping.name.to_s }
          end
        end

        # Files in the directory that carry a source's filename prefix: the
        # prefix plus an index naming the source is what adopts a file
        # written before any --prune run recorded it. An empty prefix
        # matches every file; the caller's shape check is what narrows it.
        # @param prefix [String] the source's filename prefix
        # @param output_dir [String] output directory
        # @return [Array<String>] filenames
        def prefixed_files(prefix, output_dir)
          Dir.children(output_dir).select { |name| name.start_with?(prefix) }
        rescue SystemCallError
          []
        end

        # @param source [Symbol] source code
        # @param stale [Integer] files a prune would remove
        # @param previous [Object] the previous harvest's recorded count
        # @return [Boolean] true when the files are left in place
        def prune_too_large?(source, stale, previous)
          return false if stale.zero? || options[:allow_shrink]

          limit = previous.is_a?(Integer) ? [(previous * PRUNE_CEILING).floor, 1].max : 0
          return false if stale <= limit

          warn "[#{source}] --prune left #{stale} files in place: more than " \
               "#{(PRUNE_CEILING * 100).round}% of the previous harvest " \
               "(#{previous.inspect}). Pass --allow-shrink to remove them."
          true
        end
      end
    end
  end
end
