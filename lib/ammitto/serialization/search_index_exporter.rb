# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module Ammitto
  module Serialization
    # SearchIndexExporter creates a lightweight search index for client-side search
    #
    # The website currently loads 69MB of JSON-LD data. This exporter creates
    # a lightweight (~5-10MB) search-index.json with only essential fields,
    # allowing full entity data to be loaded on-demand from node files.
    #
    # @example Using the search index exporter
    #   exporter = SearchIndexExporter.new
    #
    #   # Add entities during harmonization
    #   exporter.add(entity_hash, entry_hash)
    #
    #   # Export search index and facets
    #   exporter.export('./api/v1')
    #
    class SearchIndexExporter
      # @return [Array<Hash>] entities for search index
      attr_reader :entities

      # @return [Hash] facet counts
      attr_reader :facets

      # Authority names for facet display
      AUTHORITY_NAMES = {
        'un' => 'United Nations',
        'eu' => 'European Union',
        'uk' => 'United Kingdom',
        'us' => 'United States',
        'au' => 'Australia',
        'ca' => 'Canada',
        'ch' => 'Switzerland',
        'cn' => 'China',
        'ru' => 'Russia',
        'tr' => 'Turkey',
        'nz' => 'New Zealand',
        'jp' => 'Japan',
        'wb' => 'World Bank',
        'eu_vessels' => 'EU Vessels',
        'un_vessels' => 'UN Vessels'
      }.freeze

      # Entity type display info
      ENTITY_TYPES = {
        'person' => { name: 'Person', icon: 'user' },
        'organization' => { name: 'Organization', icon: 'building' },
        'vessel' => { name: 'Vessel', icon: 'ship' },
        'aircraft' => { name: 'Aircraft', icon: 'plane' }
      }.freeze

      # Initialize the search index exporter
      def initialize
        @entities = []
        @facets = {
          authorities: Hash.new(0),
          regimes: {},
          types: Hash.new(0),
          countries: Hash.new(0),
          statuses: Hash.new(0)
        }
      end

      # Add entity to search index
      # @param entity [Hash] full entity data
      # @param entry [Hash] sanction entry data
      # @return [void]
      def add(entity, entry)
        # Support both '@id' (JSON-LD) and 'id' (model hash) formats
        entity_id = entity['@id'] || entity['id']
        return unless entity_id

        # Extract authority code from entry
        authority_code = extract_authority_code(entry)
        regime_code = extract_regime_code(entry)

        # Extract names
        names = extract_names(entity)
        primary_name = extract_primary_name(entity)

        # Create search entity (lightweight)
        search_entity = {
          id: entity_id,
          ref: extract_ref(entity_id),
          type: entity['entityType'] || entity['entity_type'] || 'person',
          names: names,
          primaryName: primary_name,
          country: extract_country(entity),
          regime: regime_code,
          authority: authority_code,
          status: entry['status'] || 'active',
          birthYear: extract_birth_year(entity),
          imo: extract_imo(entity)
        }.compact

        @entities << search_entity
        update_facets(search_entity, regime_code, entry)
      end

      # Export search index and facets to output directory
      # @param output_dir [String] output directory path
      # @return [void]
      def export(output_dir)
        export_search_index(output_dir)
        export_facets(output_dir)
      end

      private

      # Extract reference path from entity ID
      # @param entity_id [String] full entity ID or simple ID
      # @return [String] short reference (e.g., "un/KPi.066" or "au/1234")
      def extract_ref(entity_id)
        # Try to extract from full URI format "https://www.ammitto.org/entity/un/KPi.066"
        match = entity_id.match(%r{/entity/([^/]+/[^/]+)$})
        return match[1] if match

        # If it's already in "source/ref" format, return as-is
        return entity_id if entity_id.include?('/')

        # Otherwise return the ID as-is
        entity_id
      end

      # Extract authority code from entry
      # @param entry [Hash] entry data
      # @return [String, nil] authority code
      def extract_authority_code(entry)
        return nil unless entry

        authority = entry['authority']

        # Direct string value
        return authority.downcase if authority.is_a?(String)

        # Check for @id reference
        if authority.is_a?(Hash)
          if authority['@id']
            # Extract from "https://www.ammitto.org/authority/un"
            match = authority['@id'].match(%r{/authority/([^/]+)$})
            return match[1] if match
          end
          return authority['countryCode']&.downcase
        end

        nil
      end

      # Extract regime code from entry
      # @param entry [Hash] entry data
      # @return [String, nil] regime code
      def extract_regime_code(entry)
        return nil unless entry

        # Check for @id reference
        if entry['regime'].is_a?(Hash)
          if entry['regime']['@id']
            # Extract from "https://www.ammitto.org/regime/dprk"
            match = entry['regime']['@id'].match(%r{/regime/([^/]+)$})
            return match[1] if match
          end
          return entry['regime']['code']&.downcase
        end

        nil
      end

      # Extract all names from entity
      # @param entity [Hash] entity data
      # @return [Array<String>] list of names
      def extract_names(entity)
        names = []

        # From names array
        if entity['names'].is_a?(Array)
          entity['names'].each do |name|
            if name.is_a?(Hash)
              names << name['fullName'] if name['fullName']
              names << name['lastName'] if name['lastName']
              names << name['firstName'] if name['firstName']
            elsif name.is_a?(String)
              names << name
            end
          end
        end

        # From name field
        names << entity['name'] if entity['name']

        # From aliases
        if entity['aliases'].is_a?(Array)
          entity['aliases'].each do |alias_obj|
            if alias_obj.is_a?(Hash)
              names << alias_obj['name'] if alias_obj['name']
            elsif alias_obj.is_a?(String)
              names << alias_obj
            end
          end
        end

        names.uniq.compact
      end

      # Extract primary name from entity
      # @param entity [Hash] entity data
      # @return [String, nil] primary name
      def extract_primary_name(entity)
        # From names array - find primary
        if entity['names'].is_a?(Array)
          primary = entity['names'].find do |name|
            name.is_a?(Hash) && name['isPrimary'] == true
          end
          return primary['fullName'] if primary&.dig('fullName')
        end

        # Fall back to first name
        return entity['names'].first['fullName'] if entity['names'].is_a?(Array) && entity['names'].first.is_a?(Hash)

        # Fall back to name field
        entity['name']
      end

      # Extract country from entity
      # @param entity [Hash] entity data
      # @return [String, nil] country code
      def extract_country(entity)
        # From nationality
        if entity['nationalities'].is_a?(Array) && entity['nationalities'].first
          nat = entity['nationalities'].first
          return nat['countryCode'] if nat.is_a?(Hash) && nat['countryCode']
          return nat if nat.is_a?(String)
        end

        # From citizenship
        if entity['citizenships'].is_a?(Array) && entity['citizenships'].first
          cit = entity['citizenships'].first
          return cit['countryCode'] if cit.is_a?(Hash) && cit['countryCode']
        end

        # From addresses
        if entity['addresses'].is_a?(Array) && entity['addresses'].first
          addr = entity['addresses'].first
          return addr['countryCode'] if addr.is_a?(Hash) && addr['countryCode']
          return addr['country'] if addr.is_a?(Hash) && addr['country']
        end

        # From birth info
        if entity['birthInfo'].is_a?(Array) && entity['birthInfo'].first
          birth = entity['birthInfo'].first
          return birth['countryCode'] if birth.is_a?(Hash) && birth['countryCode']
          return birth['country'] if birth.is_a?(Hash) && birth['country']
        end

        nil
      end

      # Extract birth year from entity
      # @param entity [Hash] entity data
      # @return [String, nil] birth year
      def extract_birth_year(entity)
        return nil unless entity['entityType'] == 'person'

        # From birth info
        if entity['birthInfo'].is_a?(Array) && entity['birthInfo'].first
          birth = entity['birthInfo'].first
          date = birth['date'] || birth['year']
          return date[0, 4] if date && date.length >= 4
        end

        # From birthDate
        return entity['birthDate'][0, 4] if entity['birthDate'] && (entity['birthDate'].length >= 4)

        nil
      end

      # Extract IMO number from entity (vessels)
      # @param entity [Hash] entity data
      # @return [String, nil] IMO number
      def extract_imo(entity)
        return nil unless entity['entityType'] == 'vessel'

        # From identifiers
        if entity['identifiers'].is_a?(Array)
          imo = entity['identifiers'].find do |id|
            id.is_a?(Hash) && id['type']&.downcase == 'imo'
          end
          return imo['value'] if imo
        end

        # From imo field
        entity['imo'] || entity['imoNumber']
      end

      # Update facet counts
      # @param search_entity [Hash] search entity data
      # @param regime_code [String, nil] regime code
      # @param entry [Hash] entry data
      def update_facets(search_entity, regime_code, entry)
        # Authority
        @facets[:authorities][search_entity[:authority]] += 1 if search_entity[:authority]

        # Regime
        if regime_code
          @facets[:regimes][regime_code] ||= { count: 0, name: extract_regime_name(entry) }
          @facets[:regimes][regime_code][:count] += 1
        end

        # Type
        @facets[:types][search_entity[:type]] += 1 if search_entity[:type]

        # Country
        @facets[:countries][search_entity[:country].upcase] += 1 if search_entity[:country]

        # Status
        return unless search_entity[:status]

        @facets[:statuses][search_entity[:status]] += 1
      end

      # Extract regime name from entry
      # @param entry [Hash] entry data
      # @return [String, nil] regime name
      def extract_regime_name(entry)
        return nil unless entry && entry['regime'].is_a?(Hash)

        entry['regime']['name']
      end

      # Export search index to file
      # @param output_dir [String] output directory
      def export_search_index(output_dir)
        data = {
          metadata: {
            generated: Time.now.utc.iso8601,
            totalEntities: @entities.length,
            sources: @facets[:authorities].keys.length
          },
          entities: @entities
        }

        output_path = File.join(output_dir, 'search-index.json')
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.generate(data))

        puts "Exported search index: #{@entities.length} entities to #{output_path}"
      end

      # Export facet files
      # @param output_dir [String] output directory
      def export_facets(output_dir)
        facets_dir = File.join(output_dir, 'facets')
        FileUtils.mkdir_p(facets_dir)

        # Authorities
        export_authority_facets(facets_dir)

        # Regimes
        export_regime_facets(facets_dir)

        # Types
        export_type_facets(facets_dir)

        # Countries
        export_country_facets(facets_dir)

        # Statuses
        export_status_facets(facets_dir)
      end

      # Export authority facets
      # @param dir [String] facets directory
      def export_authority_facets(dir)
        facets_data = @facets[:authorities].map do |code, count|
          {
            code: code,
            name: AUTHORITY_NAMES[code] || code.upcase,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'authorities.json'), JSON.generate(facets: facets_data))
      end

      # Export regime facets
      # @param dir [String] facets directory
      def export_regime_facets(dir)
        facets_data = @facets[:regimes].map do |code, data|
          {
            code: code,
            name: data[:name] || code.upcase,
            count: data[:count]
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'regimes.json'), JSON.generate(facets: facets_data))
      end

      # Export type facets
      # @param dir [String] facets directory
      def export_type_facets(dir)
        facets_data = @facets[:types].map do |code, count|
          type_info = ENTITY_TYPES[code] || { name: code.capitalize, icon: 'circle' }
          {
            code: code,
            name: type_info[:name],
            icon: type_info[:icon],
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'types.json'), JSON.generate(facets: facets_data))
      end

      # Export country facets
      # @param dir [String] facets directory
      def export_country_facets(dir)
        facets_data = @facets[:countries].map do |code, count|
          {
            code: code,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'countries.json'), JSON.generate(facets: facets_data))
      end

      # Export status facets
      # @param dir [String] facets directory
      def export_status_facets(dir)
        facets_data = @facets[:statuses].map do |code, count|
          {
            code: code,
            name: code.capitalize,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'statuses.json'), JSON.generate(facets: facets_data))
      end
    end
  end
end
