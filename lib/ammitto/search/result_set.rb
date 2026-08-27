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

      # Wire terms whose model attribute is not their snake_case spelling
      WIRE_KEY_ALIASES = {
        'hasSanctionEntry' => :sanction_entry_ids,
        'sanctionEntries' => :sanction_entry_ids
      }.freeze

      # @return [Array<SanctionEntry>] the results
      attr_reader :entries

      # @return [Integer] total count before pagination
      attr_reader :total_count

      # @return [String] the search term
      attr_reader :term

      # @return [Array<Symbol>] sources that could not be read for this
      #   search. Non-empty means the result set is a partial view of the
      #   corpus, and a caller screening a name must treat "no match" as
      #   inconclusive rather than negative.
      attr_reader :skipped_sources

      # Delegate array methods.
      #
      # These retain their normal Array return values, as Ruby callers
      # expect — `map` returning a ResultSet would surprise every one of
      # them. The consequence is that #skipped_sources and #complete? do
      # NOT survive `map`, `to_a` or a `[]` slice. Read completeness from
      # the result set itself before converting it, never from what a
      # conversion produced. Only the domain filters — #by_entity_type,
      # #by_authority, #by_status — return a ResultSet and carry it.
      def_delegators :entries, :[], :each, :map, :size, :length, :empty?,
                     :first, :last, :any?, :count, :to_a

      # Initialize the result set
      # @param entries [Array<Hash, SanctionEntry>] the results
      # @param term [String] the search term
      # @param total_count [Integer, nil] total count
      # @param skipped_sources [Array<Symbol>, nil] sources that could not
      #   be read; nil and [] both mean the search was complete
      def initialize(entries, term: nil, total_count: nil, skipped_sources: nil)
        @entries = normalize_entries(entries)
        @term = term
        @total_count = total_count || @entries.size
        # Frozen copy: `complete?` reads this, and a caller who mutated it
        # — or a derived set sharing the same array — could turn an
        # incomplete result into a complete-looking one.
        @skipped_sources = (skipped_sources || []).dup.freeze
      end

      # Whether every source was read.
      #
      # @return [Boolean] false when at least one source was skipped
      def complete?
        skipped_sources.empty?
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
      #
      # Guarded the way #by_authority and #by_status are, because a set
      # holds whatever the search returned: SanctionEntry has no
      # entity_type, Entity has neither authority nor status, and any of
      # the three filters can be handed a set containing both. An entry
      # simply is not an entity of the requested type, so it drops out —
      # the same answer #by_authority gives an Entity.
      #
      # @param type [Symbol, String] the entity type
      # @return [ResultSet] filtered results
      def by_entity_type(type)
        filtered = entries.select do |e|
          e.respond_to?(:entity_type) && e.entity_type == type.to_s
        end
        ResultSet.new(filtered, term: term, total_count: total_count,
                                skipped_sources: skipped_sources)
      end

      # Filter results by authority
      # @param code [Symbol, String] the authority code
      # @return [ResultSet] filtered results
      def by_authority(code)
        filtered = entries.select do |e|
          e.respond_to?(:authority) && e.authority&.id == code.to_s
        end
        ResultSet.new(filtered, term: term, total_count: total_count,
                                skipped_sources: skipped_sources)
      end

      # Filter results by status
      # @param status [Symbol, String] the status
      # @return [ResultSet] filtered results
      def by_status(status)
        filtered = entries.select do |e|
          e.respond_to?(:status) && e.status == status.to_s
        end
        ResultSet.new(filtered, term: term, total_count: total_count,
                                skipped_sources: skipped_sources)
      end

      # Get unique entity types in results
      #
      # Guarded like #authorities: a member that carries no entity_type
      # contributes nothing, rather than raising and taking the types of
      # every member that does have one down with it.
      #
      # @return [Array<String>]
      def entity_types
        entries.map { |e| e.respond_to?(:entity_type) ? e.entity_type : nil }
               .uniq.compact
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
          entities: entries.grep(Entity),
          entries: entries.grep(SanctionEntry)
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
        PersonEntity.new(normalize_model_hash(hash))
      end

      def build_organization(hash)
        OrganizationEntity.new(normalize_model_hash(hash))
      end

      def build_vessel(hash)
        VesselEntity.new(normalize_model_hash(hash))
      end

      def build_aircraft(hash)
        AircraftEntity.new(normalize_model_hash(hash))
      end

      def build_sanction_entry(hash)
        SanctionEntry.new(normalize_model_hash(hash))
      end

      def build_entity(hash)
        Entity.new(normalize_model_hash(hash))
      end

      # Recursively convert a JSON-LD hash (camelCase, @id/@type keywords)
      # into model attribute keys. snake_case input passes through unchanged,
      # so both the canonical camelCase shape and legacy snake_case data build
      # fully-populated models.
      # @param hash [Hash]
      # @return [Hash<Symbol, Object>]
      def normalize_model_hash(hash)
        # Several wire terms map onto one attribute (sanction_entry_ids /
        # sanctionEntries / hasSanctionEntry), so a node carrying more than
        # one must resolve by declared precedence rather than by whichever
        # the hash happened to list last. Ranks that matter are distinct, and
        # the source index breaks ties so equal-rank keys keep their order
        # (Enumerable#sort_by is not documented as stable).
        hash.each_with_index
            .sort_by { |(k, _), index| [wire_key_rank(k), index] }
            .each_with_object({}) do |((k, v), _index), out|
          key = normalize_model_key(k)
          next if key.nil?

          out[key] = normalize_model_value(key, v)
        end
      end

      # Lowest rank is applied first and therefore loses to anything later:
      # legacy snake_case < the deprecated sanctionEntries alias < the
      # producer's own camelCase and JSON-LD keywords.
      # @param key [String, Symbol]
      # @return [Integer]
      def wire_key_rank(key)
        str = key.to_s
        return 1 if str == 'sanctionEntries'
        return 2 if str.start_with?('@') || WIRE_KEY_ALIASES.key?(str) || str.match?(/[a-z][A-Z]/)

        0
      end

      # @param key [String, Symbol]
      # @return [Symbol, nil] nil for JSON-LD keywords that are not attributes
      def normalize_model_key(key)
        str = key.to_s
        return :id if ['@id', 'id'].include?(str)
        return nil if ['@type', '@context'].include?(str)

        WIRE_KEY_ALIASES[str] ||
          str.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
      end

      # @param key [Symbol] normalized key
      # @param value [Object]
      # @return [Object]
      def normalize_model_value(key, value)
        # Provenance payloads are opaque — never rewrite their keys
        return value if key == :source_specific_fields

        # hasSanctionEntry is @id-typed, so a value may arrive as an IRI
        # string, a set of them, or { '@id' => IRI } node references. Not
        # Kernel#Array: that turns a lone Hash into its key/value pairs.
        if key == :sanction_entry_ids
          items = value.is_a?(Array) ? value : [value]
          return items.filter_map { |item| entry_iri(item) }.uniq
        end

        case value
        when Hash
          normalize_model_hash(value)
        when Array
          value.map { |item| item.is_a?(Hash) ? normalize_model_hash(item) : item }
        else
          value
        end
      end

      # @param item [String, Hash, Object] an @id-typed value
      # @return [String, nil] the IRI, or nil when the item carries none
      def entry_iri(item)
        # ResultSet also accepts plain Ruby hashes, which may be symbol-keyed
        # rather than parsed from JSON. Take the first candidate that is a
        # usable string, so a blank or wrong-typed '@id' cannot mask a
        # perfectly good 'id'.
        candidates = item.is_a?(Hash) ? item.values_at('@id', :@id, 'id', :id) : [item]

        candidates.filter_map do |value|
          next unless value.is_a?(String)

          stripped = value.strip
          stripped.empty? ? nil : stripped
        end.first
      end
    end
  end
end
