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
          list_types: Hash.new(0),
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
        list_type = extract_list_type(entry)

        # Extract names
        names = extract_names(entity)
        primary_name = extract_primary_name(entity)

        # Support both camelCase and snake_case entity type
        entity_type = entity['entityType'] || entity['entity_type'] || 'person'

        # Create search entity (lightweight)
        search_entity = {
          id: entity_id,
          ref: extract_ref(entity_id),
          type: entity_type,
          names: names,
          primaryName: primary_name,
          country: extract_country(entity),
          regime: regime_code,
          authority: authority_code,
          listType: list_type,
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

      # Extract list type from entry
      # @param entry [Hash] entry data
      # @return [String, nil] list type
      def extract_list_type(entry)
        return nil unless entry

        # Check for list_type field (normalized structure)
        return entry['list_type'] if entry['list_type']
        return entry['listType'] if entry['listType']

        # Try to extract from entry @id
        entry_id = entry['@id'] || entry['id']
        return nil unless entry_id

        # Pattern: BASE_URI/entry/{source}/{list_type}/{local_id}
        match = entry_id.match(%r{/entry/[^/]+/([^/]+)})
        match ? match[1] : nil
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
              # Support both camelCase and snake_case keys
              names << name['fullName'] if name['fullName']
              names << name['full_name'] if name['full_name']
              names << name['lastName'] if name['lastName']
              names << name['last_name'] if name['last_name']
              names << name['firstName'] if name['firstName']
              names << name['first_name'] if name['first_name']
              names << name['middleName'] if name['middleName']
              names << name['middle_name'] if name['middle_name']
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
              names << alias_obj['full_name'] if alias_obj['full_name']
              names << alias_obj['fullName'] if alias_obj['fullName']
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
            name.is_a?(Hash) && (name['isPrimary'] == true || name['is_primary'] == true)
          end
          # Support both camelCase and snake_case
          return primary['fullName'] if primary&.dig('fullName')
          return primary['full_name'] if primary&.dig('full_name')
        end

        # Fall back to first name
        if entity['names'].is_a?(Array) && entity['names'].first.is_a?(Hash)
          first = entity['names'].first
          return first['fullName'] if first['fullName']
          return first['full_name'] if first['full_name']
        end

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
          return nat['country_code'] if nat.is_a?(Hash) && nat['country_code']
          return nat if nat.is_a?(String)
        end

        # From citizenship
        if entity['citizenships'].is_a?(Array) && entity['citizenships'].first
          cit = entity['citizenships'].first
          return cit['countryCode'] if cit.is_a?(Hash) && cit['countryCode']
          return cit['country_code'] if cit.is_a?(Hash) && cit['country_code']
        end

        # From addresses
        if entity['addresses'].is_a?(Array) && entity['addresses'].first
          addr = entity['addresses'].first
          return addr['countryCode'] if addr.is_a?(Hash) && addr['countryCode']
          return addr['country_code'] if addr.is_a?(Hash) && addr['country_code']
          return addr['country'] if addr.is_a?(Hash) && addr['country']
        end

        # From birth info
        if entity['birthInfo'].is_a?(Array) && entity['birthInfo'].first
          birth = entity['birthInfo'].first
          return birth['countryCode'] if birth.is_a?(Hash) && birth['countryCode']
          return birth['country_code'] if birth.is_a?(Hash) && birth['country_code']
          return birth['country'] if birth.is_a?(Hash) && birth['country']
        end

        # Also check birth_info (snake_case)
        if entity['birth_info'].is_a?(Array) && entity['birth_info'].first
          birth = entity['birth_info'].first
          return birth['countryCode'] if birth.is_a?(Hash) && birth['countryCode']
          return birth['country_code'] if birth.is_a?(Hash) && birth['country_code']
          return birth['country'] if birth.is_a?(Hash) && birth['country']
        end

        nil
      end

      # Extract birth year from entity
      # @param entity [Hash] entity data
      # @return [String, nil] birth year
      def extract_birth_year(entity)
        entity_type = entity['entityType'] || entity['entity_type']
        return nil unless entity_type == 'person'

        # From birth_info (snake_case)
        if entity['birth_info'].is_a?(Array) && entity['birth_info'].first
          birth = entity['birth_info'].first
          date = birth['date'] || birth['year']
          return extract_year_from_date(date) if date
        end

        # From birthInfo (camelCase)
        if entity['birthInfo'].is_a?(Array) && entity['birthInfo'].first
          birth = entity['birthInfo'].first
          date = birth['date'] || birth['year']
          return extract_year_from_date(date) if date
        end

        # From birthDate
        return extract_year_from_date(entity['birthDate']) if entity['birthDate']

        # From birth_date (snake_case)
        return extract_year_from_date(entity['birth_date']) if entity['birth_date']

        nil
      end

      # Extract year from date (handles both String and Date objects)
      # @param date [String, Date, nil] date value
      # @return [String, nil] year as string
      def extract_year_from_date(date)
        return nil unless date

        case date
        when String
          date[0, 4] if date.length >= 4
        when Date, DateTime, Time
          date.year.to_s
        else
          date.to_s[0, 4] if date.to_s.length >= 4
        end
      end

      # Extract IMO number from entity (vessels)
      # @param entity [Hash] entity data
      # @return [String, nil] IMO number
      def extract_imo(entity)
        entity_type = entity['entityType'] || entity['entity_type']
        return nil unless entity_type == 'vessel'

        # From identifiers
        if entity['identifiers'].is_a?(Array)
          imo = entity['identifiers'].find do |id|
            id.is_a?(Hash) && (id['type']&.downcase == 'imo' || id['document_type']&.downcase == 'imo')
          end
          return imo['value'] if imo && imo['value']
          return imo['identification'] if imo && imo['identification']
        end

        # From identifications (snake_case)
        if entity['identifications'].is_a?(Array)
          imo = entity['identifications'].find do |id|
            id.is_a?(Hash) && (id['type']&.downcase == 'imo' || id['document_type']&.downcase == 'imo')
          end
          return imo['value'] if imo && imo['value']
          return imo['identification'] if imo && imo['identification']
        end

        # From imo field
        entity['imo'] || entity['imoNumber'] || entity['imo_number']
      end

      # Update facet counts
      # @param search_entity [Hash] search entity data
      # @param regime_code [String, nil] regime code
      # @param entry [Hash] entry data
      def update_facets(search_entity, regime_code, entry)
        # Authority
        @facets[:authorities][search_entity[:authority]] += 1 if search_entity[:authority]

        # List type
        @facets[:list_types][search_entity[:listType]] += 1 if search_entity[:listType]

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

        # List types
        export_list_type_facets(facets_dir)

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

      # Export list type facets
      # @param dir [String] facets directory
      def export_list_type_facets(dir)
        facets_data = @facets[:list_types].map do |code, count|
          {
            code: code,
            name: format_list_type_name(code),
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'list_types.json'), JSON.generate(facets: facets_data))
      end

      # Format list type code into display name
      # @param code [String] list type code
      # @return [String] formatted name
      def format_list_type_name(code)
        code.to_s
            .gsub('-', ' ')
            .split
            .map(&:capitalize)
            .join(' ')
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
