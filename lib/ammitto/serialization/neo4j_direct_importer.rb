# frozen_string_literal: true

# Neo4j Direct Importer for Ammitto Knowledge Graph
#
# This importer reads the ontology classes directly and imports them to Neo4j
# WITHOUT using intermediate CSV files. The Ruby ontology IS the schema.
#
# Uses cypher-shell via Docker for reliability.
#
# Usage:
#   importer = Ammitto::Serialization::Neo4jDirectImporter.new(
#     container: 'ammitto-neo4j',
#     username: 'neo4j',
#     password: 'password'
#   )
#   importer.import_from_directory('/path/to/data')

require 'yaml'
require 'open3'
require_relative '../ontology'

module Ammitto
  module Serialization
    class Neo4jDirectImporter
      # Constraints and indexes are derived from the ONTOLOGY itself
      CONSTRAINTS = [
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entry) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Authority) REQUIRE n.code IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Announcement) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:LegalInstrument) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Country) REQUIRE n.code IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Regime) REQUIRE n.code IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Name) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Address) REQUIRE n.id IS UNIQUE',
        'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Identifier) REQUIRE n.id IS UNIQUE'
      ].freeze

      INDEXES = [
        'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.source)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.type)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.primary_name)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Vessel) ON (n.imo)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Entry) ON (n.list_type)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Entry) ON (n.status)',
        'CREATE INDEX IF NOT EXISTS FOR (n:Name) ON (n.full_name)'
      ].freeze

      def initialize(container: 'ammitto-neo4j', username: 'neo4j', password: 'password')
        @container = container
        @username = username
        @password = password
        @stats = { nodes: {}, relationships: {} }
      end

      # Run a Cypher query
      def run_query(query, **params)
        if params.any?
          params.each do |key, value|
            query = query.sub("$#{key}", escape_value(value))
          end
        end
        escaped_query = query

        cmd = [
          'docker', 'exec', @container,
          'cypher-shell', '-u', @username, '-p', @password,
          '--format', 'plain',
          escaped_query
        ]

        stdout, stderr, status = Open3.capture3(*cmd)
        puts "Query failed: #{stderr}" unless status.success?
        stdout
      end

      # Escape a value for Cypher
      def escape_value(value)
        return 'null' if value.nil?
        return "'#{value.to_s.gsub("'", "\\'")}'" if value.is_a?(String)

        value.to_s
      end

      # Create constraints and indexes
      def create_schema
        puts 'Creating constraints...'
        CONSTRAINTS.each do |constraint|
          run_query(constraint)
        end

        puts 'Creating indexes...'
        INDEXES.each do |index|
          run_query(index)
        end
        puts 'Schema created'
      end

      # Import all data from a base directory
      def import_from_directory(base_dir)
        create_schema
        clear_existing_data if should_clear?

        # Import authorities (single source of truth)
        import_authorities

        # Import each source
        import_all_sources(base_dir)

        # Validate
        validate_data
      end

      # Import authorities from the ontology registry
      def import_authorities
        puts 'Importing authorities...'
        count = 0

        Ammitto::Ontology.authorities.each do |code, authority|
          run_query(
            'MERGE (a:Authority {code: $code})
             SET a.name = $name, a.country_code = $country_code, a.url = $url',
            code: code,
            name: authority.name,
            country_code: authority.country_code,
            url: authority.url
          )
          count += 1
        end

        @stats[:nodes]['Authority'] = count
        puts "  Imported #{count} authorities"
      end

      # Import all sources
      def import_all_sources(base_dir)
        # Find all source directories - check both flat and nested structures
        base_paths = [
          base_dir,
          File.dirname(base_dir)
        ].uniq

        base_paths.each do |base_path|
          Dir.glob(File.join(base_path, 'data-*', 'processed')).each do |processed_dir|
            source = File.basename(File.dirname(processed_dir)).sub('data-', '')
            puts "\n=== Importing source: #{source} ==="

            # Check for list-type subdirectories
            list_dirs = Dir.glob(File.join(processed_dir, '*'))
                           .select { |d| File.directory?(d) }
                           .map { |d| File.basename(d) }

            if list_dirs.intersect?(%w[entities entries])
              # Old structure (no list-type subdirectories)
              import_source(processed_dir, source, nil)
            else
              # New structure (with list-type subdirectories)
              list_dirs.each do |list_type|
                list_dir = File.join(processed_dir, list_type)
                import_source(list_dir, source, list_type)
              end
            end
          end
        end
      end

      # Import a single source/list
      def import_source(dir, source, list_type)
        entities_dir = File.join(dir, 'entities')
        entries_dir = File.join(dir, 'entries')

        return unless File.directory?(entities_dir)

        puts "  Importing from: #{dir}"

        # Import entities
        if File.directory?(entities_dir)
          Dir.glob(File.join(entities_dir, '*.yaml')).each do |entity_file|
            import_entity(entity_file, source, list_type)
          end
        end

        # Import entries
        return unless File.directory?(entries_dir)

        Dir.glob(File.join(entries_dir, '*.yaml')).each do |entry_file|
          import_entry(entry_file, source, list_type)
        end
      end

      # Import a single entity
      def import_entity(file_path, source, _list_type)
        data = YAML.load_file(file_path)
        entity_id = data['id']
        entity_type = data['entity_type'] || data['type'] || 'entity'

        # Create entity node with appropriate label
        label = case entity_type
                when 'person' then 'Person'
                when 'organization' then 'Organization'
                when 'vessel' then 'Vessel'
                when 'aircraft' then 'Aircraft'
                else 'Entity'
                end

        primary_name = extract_primary_name(data)

        run_query(
          "MERGE (e:Entity:#{label} {id: $id})
           SET e.source = $source, e.type = $entity_type, e.primary_name = $primary_name,
               e.remarks = $remarks",
          id: entity_id,
          source: source,
          entity_type: entity_type,
          primary_name: primary_name,
          remarks: data['remarks']
        )
        @stats[:nodes]['Entity'] = (@stats[:nodes]['Entity'] || 0) + 1

        # Import names
        import_names(entity_id, data['names'] || data['name_variants'] || [])

        # Import addresses
        import_addresses(entity_id, data['addresses'] || [])

        # Import identifiers
        import_identifiers(entity_id, data['identifications'] || data['identifiers'] || [])

        # Import birth info for persons
        import_birth_info(entity_id, data['birth_info'] || data['birth']) if entity_type == 'person'
      rescue StandardError => e
        puts "  ERROR importing entity #{file_path}: #{e.message}"
      end

      # Import names for an entity
      def import_names(entity_id, names)
        names.each_with_index do |name_data, idx|
          name_id = "#{entity_id}/name/#{idx}"
          full_name = name_data['full_name'] || name_data['english'] || name_data['name']

          run_query(
            'MERGE (n:Name {id: $id})
             SET n.full_name = $full_name, n.is_primary = $is_primary,
                 n.script = $script, n.language = $language',
            id: name_id,
            full_name: full_name,
            is_primary: name_data['is_primary'],
            script: name_data['script'],
            language: name_data['language']
          )

          run_query(
            'MATCH (e:Entity {id: $entity_id}), (n:Name {id: $name_id})
             MERGE (e)-[:HAS_NAME]->(n)',
            entity_id: entity_id,
            name_id: name_id
          )
          @stats[:nodes]['Name'] = (@stats[:nodes]['Name'] || 0) + 1
          @stats[:relationships]['HAS_NAME'] = (@stats[:relationships]['HAS_NAME'] || 0) + 1
        end
      end

      # Import addresses for an entity
      def import_addresses(entity_id, addresses)
        addresses.each_with_index do |addr_data, idx|
          addr_id = "#{entity_id}/address/#{idx}"

          run_query(
            'MERGE (a:Address {id: $id})
             SET a.street = $street, a.city = $city, a.state = $state,
                 a.postal_code = $postal_code, a.care_of = $care_of',
            id: addr_id,
            street: addr_data['street'],
            city: addr_data['city'],
            state: addr_data['state'],
            postal_code: addr_data['postal_code'],
            care_of: addr_data['care_of']
          )

          run_query(
            'MATCH (e:Entity {id: $entity_id}), (a:Address {id: $addr_id})
             MERGE (e)-[:HAS_ADDRESS]->(a)',
            entity_id: entity_id,
            addr_id: addr_id
          )
          @stats[:nodes]['Address'] = (@stats[:nodes]['Address'] || 0) + 1
          @stats[:relationships]['HAS_ADDRESS'] = (@stats[:relationships]['HAS_ADDRESS'] || 0) + 1

          # Import country relationship
          next unless addr_data['country_code'] || addr_data['country']

          country_code = addr_data['country_code'] || addr_data['country']
          import_country(country_code)
          run_query(
            'MATCH (a:Address {id: $addr_id}), (c:Country {code: $country_code})
             MERGE (a)-[:IN_COUNTRY]->(c)',
            addr_id: addr_id,
            country_code: country_code
          )
          @stats[:relationships]['IN_COUNTRY'] = (@stats[:relationships]['IN_COUNTRY'] || 0) + 1
        end
      end

      # Import identifiers for an entity
      def import_identifiers(entity_id, identifiers)
        identifiers.each_with_index do |id_data, idx|
          identifier_id = "#{entity_id}/identifier/#{idx}"

          run_query(
            'MERGE (i:Identifier {id: $id})
             SET i.type = $type, i.value = $value, i.issue_date = $issue_date,
                 i.expiry_date = $expiry_date',
            id: identifier_id,
            type: id_data['type'] || id_data['id_type'],
            value: id_data['value'] || id_data['id_number'],
            issue_date: id_data['issue_date'],
            expiry_date: id_data['expiry_date']
          )

          run_query(
            'MATCH (e:Entity {id: $entity_id}), (i:Identifier {id: $identifier_id})
             MERGE (e)-[:HAS_IDENTIFIER]->(i)',
            entity_id: entity_id,
            identifier_id: identifier_id
          )
          @stats[:nodes]['Identifier'] = (@stats[:nodes]['Identifier'] || 0) + 1
          @stats[:relationships]['HAS_IDENTIFIER'] = (@stats[:relationships]['HAS_IDENTIFIER'] || 0) + 1

          # Import country relationship
          next unless id_data['country_code'] || id_data['issuing_country']

          country_code = id_data['country_code'] || id_data['issuing_country']
          import_country(country_code)
          run_query(
            'MATCH (i:Identifier {id: $identifier_id}), (c:Country {code: $country_code})
             MERGE (i)-[:ISSUED_BY]->(c)',
            identifier_id: identifier_id,
            country_code: country_code
          )
          @stats[:relationships]['ISSUED_BY'] = (@stats[:relationships]['ISSUED_BY'] || 0) + 1
        end
      end

      # Import birth info
      def import_birth_info(entity_id, birth_info)
        return unless birth_info

        return unless birth_info['country_code'] || birth_info['country']

        country_code = birth_info['country_code'] || birth_info['country']
        import_country(country_code)
        run_query(
          'MATCH (e:Entity {id: $entity_id}), (c:Country {code: $country_code})
             MERGE (e)-[:BORN_IN]->(c)',
          entity_id: entity_id,
          country_code: country_code
        )
        @stats[:relationships]['BORN_IN'] = (@stats[:relationships]['BORN_IN'] || 0) + 1
      end

      # Import a single entry
      def import_entry(file_path, source, list_type)
        data = YAML.load_file(file_path)
        entry_id = data['id']
        entity_id = data['entity_id']
        authority_code = data['authority'] || data['authority_code'] || source

        # Create entry node
        period = data['period'] || {}
        run_query(
          'MERGE (e:Entry {id: $id})
           SET e.list_type = $list_type, e.status = $status,
               e.listed_date = $listed_date, e.delisted_date = $delisted_date,
               e.measures = $measures, e.reference_number = $reference_number,
               e.remarks = $remarks',
          id: entry_id,
          list_type: list_type || data['list_type'],
          status: data['status'] || 'active',
          listed_date: period['start_date'] || data['listed_date'],
          delisted_date: period['end_date'] || data['delisted_date'],
          measures: extract_measures(data),
          reference_number: data['reference_number'],
          remarks: data['remarks']
        )
        @stats[:nodes]['Entry'] = (@stats[:nodes]['Entry'] || 0) + 1

        # Link to entity
        if entity_id
          run_query(
            'MATCH (entry:Entry {id: $entry_id}), (entity:Entity {id: $entity_id})
             MERGE (entry)-[:FOR_ENTITY]->(entity)',
            entry_id: entry_id,
            entity_id: entity_id
          )
          @stats[:relationships]['FOR_ENTITY'] = (@stats[:relationships]['FOR_ENTITY'] || 0) + 1
        end

        # Link to authority
        run_query(
          'MATCH (entry:Entry {id: $entry_id}), (auth:Authority {code: $authority_code})
           MERGE (entry)-[:LISTED_BY]->(auth)',
          entry_id: entry_id,
          authority_code: authority_code
        )
        @stats[:relationships]['LISTED_BY'] = (@stats[:relationships]['LISTED_BY'] || 0) + 1

        # Link to regime if present
        if data['regime'] && data['regime']['code']
          import_regime(data['regime'])
          run_query(
            'MATCH (entry:Entry {id: $entry_id}), (r:Regime {code: $regime_code})
             MERGE (entry)-[:UNDER_REGIME]->(r)',
            entry_id: entry_id,
            regime_code: data['regime']['code']
          )
          @stats[:relationships]['UNDER_REGIME'] = (@stats[:relationships]['UNDER_REGIME'] || 0) + 1
        end
      rescue StandardError => e
        puts "  ERROR importing entry #{file_path}: #{e.message}"
      end

      # Import a country
      def import_country(code)
        return unless code

        run_query(
          'MERGE (c:Country {code: $code})',
          code: code
        )
        @stats[:nodes]['Country'] = (@stats[:nodes]['Country'] || 0) + 1
      end

      # Import a regime
      def import_regime(regime_data)
        return unless regime_data

        run_query(
          'MERGE (r:Regime {code: $code})
           SET r.name = $name, r.description = $description',
          code: regime_data['code'],
          name: regime_data['name'],
          description: regime_data['description']
        )
        @stats[:nodes]['Regime'] = (@stats[:nodes]['Regime'] || 0) + 1
      end

      # Validate the imported data
      def validate_data
        puts "\n=== Validation ==="

        # Node counts
        puts 'Node counts:'
        result = run_query(
          'MATCH (n) RETURN labels(n)[0] as type, count(n) as count ORDER BY count DESC'
        )
        puts result

        # Relationship counts
        puts "\nRelationship counts:"
        result = run_query(
          'MATCH ()-[r]->() RETURN type(r) as type, count(r) as count ORDER BY count DESC'
        )
        puts result

        # Data quality checks
        puts "\nData quality checks:"

        checks = [
          ['Entries without entity link',
           'MATCH (entry:Entry) WHERE NOT (entry)-[:FOR_ENTITY]->() RETURN count(entry)'],
          ['Entries without authority link',
           'MATCH (entry:Entry) WHERE NOT (entry)-[:LISTED_BY]->() RETURN count(entry)'],
          ['Entities without names',
           'MATCH (e:Entity) WHERE NOT (e)-[:HAS_NAME]->() RETURN count(e)'],
          ['Orphaned names',
           'MATCH (n:Name) WHERE NOT (n)<-[:HAS_NAME]-() RETURN count(n)']
        ]

        all_passed = true
        checks.each do |name, query|
          result = run_query(query)
          count = result.strip.to_i
          status = count.zero? ? '✓ PASS' : '✗ FAIL'
          puts "  #{status}: #{name} (#{count})"
          all_passed = false if count.positive?
        end

        puts "\n#{all_passed ? '✓ All validations passed' : '✗ Some validations failed'}"
        all_passed
      end

      # Print import statistics
      def print_stats
        puts "\n=== Import Statistics ==="
        puts 'Nodes:'
        @stats[:nodes].sort_by { |_, v| -v }.each do |type, count|
          puts "  #{type}: #{count}"
        end
        puts "\nRelationships:"
        @stats[:relationships].sort_by { |_, v| -v }.each do |type, count|
          puts "  #{type}: #{count}"
        end
      end

      private

      def extract_primary_name(data)
        names = data['names'] || data['name_variants'] || []
        primary = names.find { |n| n['is_primary'] }
        primary ? (primary['full_name'] || primary['english'] || primary['name']) : (names.first&.dig('full_name') || names.first&.dig('english') || names.first&.dig('name'))
      end

      def extract_measures(data)
        effects = data['effects'] || data['measures'] || []
        effects = [effects] if effects.is_a?(String)
        effects.map { |e| e['effect_type'] || e['type'] || e }.compact.join('; ')
      end

      def should_clear?
        ENV['CLEAR_NEO4J'] == 'true'
      end

      def clear_existing_data
        puts 'Clearing existing data...'
        run_query('MATCH (n) DETACH DELETE n')
      end
    end
  end
end
