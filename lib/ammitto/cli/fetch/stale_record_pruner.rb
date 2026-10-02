# frozen_string_literal: true

require 'yaml'
require_relative 'item_mapper'

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
      # so every doubt leaves the files where they are. Only a file the
      # previous --prune run recorded as its own in the index is a
      # candidate: a directory can hold files of other sources under the
      # same unprefixed names, and nothing else tells them apart.
      module StaleRecordPruner
        # The largest share of the previous harvest one run may remove.
        # Delistings arrive a few at a time; a larger drop is more likely a
        # parser that matched only part of the document, which the 50%
        # collapse guard lets through. Above this the files stay and the
        # run says why; --allow-shrink accepts the drop.
        PRUNE_CEILING = 0.05

        private

        # Delete record files this source wrote before and this run did not.
        #
        # Called only after write_items returned, so a harvest it refused
        # never reaches here. An empty harvest is skipped explicitly: with
        # nothing written, every recorded file would look stale. An index
        # without a files list names no owned files, so that run
        # only records the list and removes nothing.
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
        # moment of deletion. This narrows the window and does not close
        # it: --prune does not lock the directory.
        #
        # @param source [Symbol] source code
        # @param name [String] file to remove
        # @param output_dir [String] output directory
        # @return [Boolean] true when the file was removed
        def delete_if_still_owned(source, name, output_dir)
          current = previous_index(source, output_dir)
          files = current && current['files']
          return false unless files.is_a?(Array) && files.include?(name)

          File.delete(File.join(output_dir, name))
          true
        rescue SystemCallError
          false
        end

        # Owned files a run left in place, which the next index must keep
        # naming. Without this a file the ceiling spared would drop out of
        # `files` and no later run, even with --allow-shrink, could remove
        # it. Called after prune_stale_records: a file it deleted no longer
        # exists and falls out of the candidates.
        #
        # @param source [Symbol] source code
        # @param written [Hash{String => Array}] filenames this run wrote
        # @param output_dir [String] output directory
        # @return [Array<String>] sorted filenames still owned and present
        def retained_records(source, written, output_dir)
          return [] unless options[:prune]
          return [] if options[:output_dir] && @sources.uniq.size > 1

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
        # @param source [Symbol] source code
        # @return [Boolean]
        def shared_output_dir?(source)
          return false unless options[:output_dir] && @sources.uniq.size > 1

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
          owned = previous['files']
          return [] if prefix.nil? || !owned.is_a?(Array)

          owned.select do |name|
            name.is_a?(String) && name == File.basename(name) &&
              name.end_with?('.yaml') && name != '_index.yaml' &&
              name.start_with?(prefix) && !written.key?(name) &&
              File.file?(File.join(output_dir, name))
          end.sort
        end

        # @param source [Symbol] source code
        # @param stale [Integer] files a prune would remove
        # @param previous [Object] the previous harvest's recorded count
        # @return [Boolean] true when the files are left in place
        def prune_too_large?(source, stale, previous)
          return false if stale.zero? || options[:allow_shrink]

          limit = previous.is_a?(Integer) ? (previous * PRUNE_CEILING).floor : 0
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
