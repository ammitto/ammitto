# frozen_string_literal: true

require 'forwardable'

module Ammitto
  module Search
    # ResultSet wraps search results with convenience methods
    #
    # @example Using ResultSet
    #   results = Ammitto.search("Kim")
    #   results.each do |entry|
    #     puts entry.display_name
    #   end
    #
    class ResultSet
      extend Forwardable

      # @return [Array<SanctionEntry>] the results
      attr_reader :entries

      # @return [Integer] total count before pagination
      attr_reader :total_count

      # @return [String] the search term
      attr_reader :term

      # Delegate array methods
      def_delegators :entries, :[], :each, :map, :size, :length, :empty?,
                     :first, :last, :any?, :count, :to_a

      # Initialize the result set
      # @param entries [Array<Hash, SanctionEntry>] the results
      # @param term [String] the search term
      # @param total_count [Integer, nil] total count
      def initialize(entries, term: nil, total_count: nil)
        @entries = normalize_entries(entries)
        @term = term
        @total_count = total_count || @entries.size
      end

      # Check if results are empty
      # @return [Boolean]
      def empty?
        entries.empty?
      end

      # Get result count
      # @return [Integer]
      def size
        entries.size
      end
      alias length size

      # Filter results by entity type
      # @param type [Symbol, String] the entity type
      # @return [ResultSet] filtered results
      def by_entity_type(type)
        filtered = entries.select { |e| e.entity_type == type.to_s }
        ResultSet.new(filtered, term: term, total_count: total_count)
      end

      # Filter results by authority
      # @param code [Symbol, String] the authority code
      # @return [ResultSet] filtered results
      def by_authority(code)
        filtered = entries.select do |e|
          e.respond_to?(:authority) && e.authority&.id == code.to_s
        end
        ResultSet.new(filtered, term: term, total_count: total_count)
      end

      # Filter results by status
      # @param status [Symbol, String] the status
      # @return [ResultSet] filtered results
      def by_status(status)
        filtered = entries.select do |e|
          e.respond_to?(:status) && e.status == status.to_s
        end
        ResultSet.new(filtered, term: term, total_count: total_count)
      end

      # Get unique entity types in results
      # @return [Array<String>]
      def entity_types
        entries.map(&:entity_type).uniq.compact
      end

      # Get unique authorities in results
      # @return [Array<String>]
      def authorities
        entries.map { |e| e.respond_to?(:authority) ? e.authority&.id : nil }
               .uniq.compact
      end

      # Convert to JSON-LD format
      # @return [Hash] JSON-LD document
      def to_json_ld
        serializer = Serialization::JsonLdSerializer.new
        serializer.serialize_document(
          entities: entries.select { |e| e.is_a?(Entity) },
          entries: entries.select { |e| e.is_a?(SanctionEntry) }
        )
      end

      # Convert to JSON string
      # @return [String]
      def to_json(*_args)
        MultiJson.dump(to_json_ld, pretty: true)
      end

      private

      # Normalize entries to objects
      # @param entries [Array] the raw entries
      # @return [Array<SanctionEntry, Entity>]
      def normalize_entries(entries)
        entries.map do |entry|
          case entry
          when SanctionEntry, Entity
            entry
          when Hash
            build_from_hash(entry)
          else
            entry
          end
        end
      end

      # Build an object from a hash
      # @param hash [Hash] the data
      # @return [SanctionEntry, Entity]
      def build_from_hash(hash)
        type = hash['entityType'] || hash['entity_type'] || hash['@type']

        case type
        when 'person', 'PersonEntity'
          build_person(hash)
        when 'organization', 'OrganizationEntity'
          build_organization(hash)
        when 'vessel', 'VesselEntity'
          build_vessel(hash)
        when 'aircraft', 'AircraftEntity'
          build_aircraft(hash)
        when 'SanctionEntry'
          build_sanction_entry(hash)
        else
          build_entity(hash)
        end
      end

      def build_person(hash)
        PersonEntity.new(symbolize_keys(hash))
      end

      def build_organization(hash)
        OrganizationEntity.new(symbolize_keys(hash))
      end

      def build_vessel(hash)
        VesselEntity.new(symbolize_keys(hash))
      end

      def build_aircraft(hash)
        AircraftEntity.new(symbolize_keys(hash))
      end

      def build_sanction_entry(hash)
        SanctionEntry.new(symbolize_keys(hash))
      end

      def build_entity(hash)
        Entity.new(symbolize_keys(hash))
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
      end
    end
  end
end
