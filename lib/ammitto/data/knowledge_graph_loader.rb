# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative '../utils/iri_sanitizer'
# Same shape: `harmonize_names` calls Types.detect_script inside the
# method, so loading this file alone succeeds and the call raises.
require_relative '../ontology/types'

module Ammitto
  module Data
    # KnowledgeGraphLoader loads data from data-* repositories that use
    # the knowledge graph structure with NORMALIZED data:
    #
    # == Normalized Directory Structure
    #
    #   processed/
    #   ├── entities/                      # NORMALIZED - unique per source
    #   │   ├── marco-rubio.yaml
    #   │   └── mitsubishi-heavy-industries.yaml
    #   ├── entries/                       # Links entity to list via list_type field
    #   │   ├── entry-marco-rubio-anti-sanction.yaml
    #   │   └── entry-mitsubishi-import-export.yaml
    #   ├── announcements/                 # NORMALIZED - can affect multiple lists
    #   │   └── mofcom-2026-11.yaml
    #   ├── legal_instruments/             # NORMALIZED - can authorize multiple lists
    #   │   └── export-control-law.yaml
    #   ├── lists/                         # List definitions
    #   │   ├── anti-sanction-list.yaml
    #   │   └── import-export-control-list.yaml
    #   └── _index.yaml
    #
    # == IRI Structure
    #
    #   # Entities - LIST-AGNOSTIC (can be on multiple lists)
    #   https://www.ammitto.org/entity/{source}/{local_id}
    #
    #   # Entries - LIST-SPECIFIC (junction records)
    #   https://www.ammitto.org/entry/{source}/{list_type}/{local_id}
    #
    #   # Announcements - LIST-AGNOSTIC
    #   https://www.ammitto.org/announcement/{source}/{local_id}
    #
    #   # Legal Instruments - LIST-AGNOSTIC
    #   https://www.ammitto.org/legal_instrument/{source}/{local_id}
    #
    #   # Lists
    #   https://www.ammitto.org/list/{source}/{list_type}
    #
    # @example Loading CN data
    #   loader = Ammitto::Data::KnowledgeGraphLoader.new('/path/to/data-cn/processed')
    #   loader.source_code # => "cn"
    #   entities = loader.load_entities
    #   entries = loader.load_entries
    #   lists = loader.load_lists
    #
    class KnowledgeGraphLoader
      attr_reader :processed_dir, :source_code

      # Initialize a new KnowledgeGraphLoader.
      #
      # @param processed_dir [String] Path to the processed/ directory
      #
      def initialize(processed_dir)
        @processed_dir = processed_dir
        @source_code = detect_source_code
      end

      # Load the index file.
      #
      # @return [Hash, nil] Index data or nil if not found
      #
      def load_index
        index_path = File.join(processed_dir, '_index.yaml')
        return nil unless File.exist?(index_path)

        YAML.load_file(index_path)
      end

      # Load all entities (NORMALIZED - not per-list).
      #
      # @return [Array<Hash>] Array of entity hashes
      #
      def load_entities
        load_yaml_files(File.join(processed_dir, 'entities'))
      end

      # Load all entries (contain list_type to reference lists).
      #
      # @return [Array<Hash>] Array of entry hashes
      #
      def load_entries
        load_yaml_files(File.join(processed_dir, 'entries'))
      end

      # Load all announcements (NORMALIZED - can affect multiple lists).
      #
      # @return [Array<Hash>] Array of announcement hashes
      #
      def load_announcements
        load_yaml_files(File.join(processed_dir, 'announcements'))
      end

      # Load all legal instruments (NORMALIZED - can authorize multiple lists).
      #
      # @return [Array<Hash>] Array of legal instrument hashes
      #
      def load_legal_instruments
        load_yaml_files(File.join(processed_dir, 'legal_instruments'))
      end

      # Load all lists (list definitions).
      #
      # @return [Array<Hash>] Array of list hashes
      #
      def load_lists
        load_yaml_files(File.join(processed_dir, 'lists'))
      end

      # Load an entity by ID.
      #
      # @param id [String] Entity ID (local, without source prefix)
      # @return [Hash, nil] Entity data or nil if not found
      #
      def load_entity(id)
        load_yaml_file(File.join(processed_dir, 'entities', "#{id}.yaml"))
      end

      # Load an entry by ID.
      #
      # @param id [String] Entry ID
      # @return [Hash, nil] Entry data or nil if not found
      #
      def load_entry(id)
        load_yaml_file(File.join(processed_dir, 'entries', "#{id}.yaml"))
      end

      # Load an announcement by ID.
      #
      # @param id [String] Announcement ID
      # @return [Hash, nil] Announcement data or nil if not found
      #
      def load_announcement(id)
        load_yaml_file(File.join(processed_dir, 'announcements', "#{id}.yaml"))
      end

      # Load a legal instrument by ID.
      #
      # @param id [String] Legal instrument ID
      # @return [Hash, nil] Legal instrument data or nil if not found
      #
      def load_legal_instrument(id)
        load_yaml_file(File.join(processed_dir, 'legal_instruments', "#{id}.yaml"))
      end

      # Load a list by ID.
      #
      # @param id [String] List ID (list_type)
      # @return [Hash, nil] List data or nil if not found
      #
      def load_list(id)
        load_yaml_file(File.join(processed_dir, 'lists', "#{id}.yaml"))
      end

      # Get entries for a specific entity (across all lists).
      #
      # @param entity_id [String] Entity ID
      # @return [Array<Hash>] Array of entries for this entity
      #
      def entries_for_entity(entity_id)
        load_entries.select { |e| e['entity_id'] == entity_id }
      end

      # Get entries for a specific list.
      #
      # @param list_type [String] List type identifier
      # @return [Array<Hash>] Array of entries for this list
      #
      def entries_for_list(list_type)
        load_entries.select { |e| e['list_type'] == list_type }
      end

      # Get available list types for this source.
      #
      # @return [Array<String>] List of list type identifiers
      #
      def available_list_types
        lists = load_lists
        return Utils::ListTypesRegistry.list_types_for(source_code)&.keys || [] if lists.empty?

        lists.map { |l| l['id'] }
      end

      # Get statistics about the knowledge graph.
      #
      # @return [Hash] Statistics
      #
      def stats
        {
          source: source_code,
          entities: count_files('entities'),
          entries: count_files('entries'),
          announcements: count_files('announcements'),
          legal_instruments: count_files('legal_instruments'),
          lists: count_files('lists'),
          list_types: available_list_types
        }
      end

      # Validate the knowledge graph integrity.
      #
      # @return [Hash] Validation results
      #
      def validate
        results = {
          valid: true,
          errors: [],
          warnings: []
        }

        # Check directory structure
        %w[entities entries].each do |dir|
          dir_path = File.join(processed_dir, dir)
          unless File.directory?(dir_path)
            results[:errors] << "Missing directory: #{dir}"
            results[:valid] = false
          end
        end

        # Check for orphan entries (entries without matching entities)
        entries = load_entries
        entity_ids = load_entities.map { |e| e['id'] }

        entries.each do |entry|
          unless entity_ids.include?(entry['entity_id'])
            results[:errors] << "Orphan entry: #{entry['id']} references missing entity #{entry['entity_id']}"
            results[:valid] = false
          end
        end

        # Check for entries without valid list_type
        available_list_types
        entries.each do |entry|
          results[:warnings] << "Entry #{entry['id']} has no list_type" unless entry['list_type']
        end

        # Check for orphan entries (entries without matching announcements)
        announcement_ids = load_announcements.map { |a| a['id'] }

        entries.each do |entry|
          if entry['announcement_id'] && !announcement_ids.include?(entry['announcement_id'])
            results[:warnings] << "Entry #{entry['id']} references missing announcement #{entry['announcement_id']}"
          end
        end

        results
      end

      # Convert to harmonized ontology format.
      #
      # @return [Hash] Harmonized data structure
      #
      def to_harmonized
        {
          source: source_code,
          index: load_index,
          entities: load_entities.map { |e| harmonize_entity(e) },
          entries: load_entries.map { |e| harmonize_entry(e) },
          announcements: load_announcements.map { |a| harmonize_announcement(a) },
          legal_instruments: load_legal_instruments.map { |li| harmonize_legal_instrument(li) },
          lists: load_lists.map { |l| harmonize_list(l) }
        }
      end

      # Generate an entity IRI (LIST-AGNOSTIC).
      #
      # @param local_id [String] Local entity ID
      # @return [String] Full entity IRI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def entity_iri(local_id)
        Utils::IriSanitizer.entity_iri(source_code, local_id)
      end

      # Generate an entry IRI (LIST-SPECIFIC).
      #
      # @param list_type [String] List type
      # @param local_id [String] Local entry ID
      # @return [String] Full entry IRI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def entry_iri(list_type, local_id)
        Utils::IriSanitizer.entry_iri(source_code, list_type, local_id)
      end

      # Generate an announcement IRI (LIST-AGNOSTIC).
      #
      # @param local_id [String] Local announcement ID
      # @return [String] Full announcement IRI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def announcement_iri(local_id)
        Utils::IriSanitizer.announcement_iri(source_code, local_id)
      end

      # Generate a legal instrument IRI (LIST-AGNOSTIC).
      #
      # @param local_id [String] Local legal instrument ID
      # @return [String] Full legal instrument IRI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def legal_instrument_iri(local_id)
        Utils::IriSanitizer.legal_instrument_iri(source_code, local_id)
      end

      # Generate a list IRI.
      #
      # @param list_type [String] List type
      # @return [String] Full list IRI
      #
      def list_iri(list_type)
        Utils::IriSanitizer.list_type_iri(source_code, list_type)
      end

      private

      def detect_source_code
        # First, check index file
        index = load_index
        return index['source'] if index && index['source']

        # Try to detect from directory structure
        # Walk up to find data-XXX directory
        current = processed_dir
        while current && current != '/'
          basename = File.basename(current)
          return Regexp.last_match(1) if basename =~ /\Adata-([a-z0-9-]+)\z/

          current = File.dirname(current)
        end

        # Fallback: use grandparent directory name
        dirname = File.basename(File.dirname(processed_dir, 2))
        dirname.gsub(/^data-/, '')
      end

      def load_yaml_files(dir)
        return [] unless File.directory?(dir)

        Dir.glob(File.join(dir, '*.yaml')).map do |file|
          YAML.load_file(file)
        end.compact
      end

      def load_yaml_file(path)
        return nil unless File.exist?(path)

        YAML.load_file(path)
      end

      def count_files(subdir)
        dir_path = File.join(processed_dir, subdir)
        return 0 unless File.directory?(dir_path)

        Dir.glob(File.join(dir_path, '*.yaml')).count
      end

      def harmonize_entity(entity)
        local_id = entity['id']

        {
          'id' => entity_iri(local_id),
          'entity_type' => entity['entity_type'] || entity['type'],
          'names' => harmonize_names(entity['names']),
          'source' => source_code,
          'source_references' => [{
            'source_code' => source_code,
            'reference_number' => local_id
          }],
          'remarks' => entity['remarks']
        }.tap do |h|
          h['person_details'] = entity['person_details'] if entity['person_details']
          h['organization_details'] = entity['organization_details'] if entity['organization_details']
          h['vessel_details'] = entity['vessel_details'] if entity['vessel_details']
        end
      end

      def harmonize_names(names)
        return [] unless names

        result = []
        names.each do |name|
          # New format: already has full_name - just pass through with script detection if needed
          if name['full_name']
            result << {
              'full_name' => name['full_name'],
              'is_primary' => name['is_primary'] || false,
              'script' => name['script'] || Ammitto::Ontology::Types.detect_script(name['full_name']).to_s
            }
            next
          end

          # Old format: language-specific keys - convert using script detection
          # Iterate over all keys that look like names (not metadata like is_primary)
          name.each_key do |key|
            next if %w[is_primary script].include?(key)
            next unless name[key].is_a?(String) && !name[key].empty?

            result << {
              'full_name' => name[key],
              'is_primary' => key == (name.keys - %w[is_primary script]).first && name['is_primary'],
              'script' => Ammitto::Ontology::Types.detect_script(name[key]).to_s
            }
          end
        end

        # Ensure at least one name is marked primary
        result.first['is_primary'] = true if result.any? && result.none? { |n| n['is_primary'] }

        result
      end

      def harmonize_entry(entry)
        list_type = entry['list_type']
        local_id = entry['id']

        {
          'id' => entry_iri(list_type, local_id),
          'entity_id' => entity_iri(entry['entity_id']),
          'authority' => source_code,
          'list_id' => list_iri(list_type),
          'list_type' => list_type,
          'announcement_id' => entry['announcement_id'] ? announcement_iri(entry['announcement_id']) : nil,
          'status' => entry['status'],
          'listed_date' => entry['listed_date'],
          'delisted_date' => entry['delisted_date'],
          'measures' => entry['measures'],
          'legal_instrument_ids' => (entry['legal_instrument_ids'] || []).map do |li_id|
            legal_instrument_iri(li_id)
          end
        }.compact
      end

      def harmonize_announcement(announcement)
        local_id = announcement['id']

        {
          'id' => announcement_iri(local_id),
          'number' => announcement['number'],
          'title' => announcement['title'],
          'date' => announcement['date'],
          'effective_date' => announcement['effective_date'],
          'issuing_authority' => announcement['issuing_authority'],
          'source_url' => announcement['source_url'],
          'measures' => announcement['measures'],
          'reason' => announcement['reason']
        }.compact
      end

      def harmonize_legal_instrument(instrument)
        local_id = instrument['id']

        {
          'id' => legal_instrument_iri(local_id),
          'name_english' => instrument['name_english'],
          'name_chinese' => instrument['name_chinese'],
          'name_russian' => instrument['name_russian'],
          'short_name' => instrument['short_name'],
          'enacted_date' => instrument['enacted_date'],
          'amended_date' => instrument['amended_date']
        }.compact
      end

      def harmonize_list(list)
        list_type = list['id']

        {
          'id' => list_iri(list_type),
          'source' => source_code,
          'name' => list['name'],
          'name_chinese' => list['name_chinese'],
          'name_russian' => list['name_russian'],
          'authority' => list['authority'],
          'description' => list['description'],
          'url' => list['url'],
          'established_date' => list['established_date'],
          'legal_instrument_ids' => (list['legal_instrument_ids'] || []).map do |li_id|
            legal_instrument_iri(li_id)
          end
        }.compact
      end
    end
  end
end
