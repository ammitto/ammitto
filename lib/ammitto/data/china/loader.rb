# frozen_string_literal: true

require 'yaml'
require 'fileutils'
begin
  require 'sqlite3'
rescue LoadError
  # sqlite3 not available - Loader functionality will be limited
end

module Ammitto
  module Data
    module China
      # Loads China sanctions data into a SQLite database for testing
      #
      # Loader creates an in-memory or file-based SQLite database and loads
      # processed China sanctions data, then runs integrity tests to verify
      # data consistency.
      #
      # @example Basic usage
      #   loader = Loader.new
      #   loader.load_from_directory('processed/')
      #   success = loader.run_integrity_tests
      #
      # @example With custom database path
      #   loader = Loader.new('custom.db')
      #   loader.load_from_directory('processed/')
      #
      class Loader
        attr_reader :db_path, :db

        # Initialize the loader
        # @param db_path [String] Path to SQLite database (default: in-memory)
        def initialize(db_path = ':memory:')
          @db_path = db_path
          @db = nil
        end

        # Load all data from a processed directory
        # @param processed_dir [String] Path to processed directory
        # @return [void]
        def load_from_directory(processed_dir)
          FileUtils.rm_f(@db_path) unless @db_path == ':memory:'
          @db = SQLite3::Database.new(@db_path)
          @db.results_as_hash = true
          create_schema

          puts "Loading from: #{processed_dir}"
          load_legal_instruments(File.join(processed_dir, 'legal_instruments'))
          load_announcements(File.join(processed_dir, 'announcements'))
          load_entities(File.join(processed_dir, 'entities'))
          load_entries(File.join(processed_dir, 'entries'))
          puts 'Load complete.'
        end

        # Run integrity tests on loaded data
        # @return [Boolean] true if all tests pass
        # rubocop:disable Metrics/MethodLength
        def run_integrity_tests?
          puts "\n=== Knowledge Graph Integrity Tests ==="

          tests_passed = 0
          tests_failed = 0

          # Test 1: Count all entities
          count = @db.get_first_value('SELECT COUNT(*) FROM entities')
          if count.positive?
            puts "[PASS] Test 1 - Entity count: #{count}"
            tests_passed += 1
          else
            puts "[FAIL] Test 1 - Entity count: #{count} (expected > 0)"
            tests_failed += 1
          end

          # Test 2: Count all entries
          count = @db.get_first_value('SELECT COUNT(*) FROM sanction_entries')
          if count.positive?
            puts "[PASS] Test 2 - Entry count: #{count}"
            tests_passed += 1
          else
            puts "[FAIL] Test 2 - Entry count: #{count} (expected > 0)"
            tests_failed += 1
          end

          # Test 3: Verify all entries have valid entity references
          orphans = @db.get_first_value(<<~SQL)
            SELECT COUNT(*) FROM sanction_entries e
            LEFT JOIN entities ent ON e.entity_id = ent.id
            WHERE ent.id IS NULL
          SQL
          if orphans.zero?
            puts "[PASS] Test 3 - Orphan entries (entity): #{orphans}"
            tests_passed += 1
          else
            puts "[FAIL] Test 3 - Orphan entries (entity): #{orphans}"
            tests_failed += 1
          end

          # Test 4: Verify all entries have valid announcement references
          orphans = @db.get_first_value(<<~SQL)
            SELECT COUNT(*) FROM sanction_entries e
            LEFT JOIN announcements a ON e.announcement_id = a.id
            WHERE a.id IS NULL
          SQL
          if orphans.zero?
            puts "[PASS] Test 4 - Orphan entries (announcement): #{orphans}"
            tests_passed += 1
          else
            puts "[FAIL] Test 4 - Orphan entries (announcement): #{orphans}"
            tests_failed += 1
          end

          # Test 5: Verify all legal instrument references are valid
          orphans = @db.get_first_value(<<~SQL)
            SELECT COUNT(*) FROM entry_legal_instruments eli
            LEFT JOIN legal_instruments li ON eli.legal_instrument_id = li.id
            WHERE li.id IS NULL
          SQL
          if orphans.zero?
            puts "[PASS] Test 5 - Orphan legal instrument refs: #{orphans}"
            tests_passed += 1
          else
            puts "[FAIL] Test 5 - Orphan legal instrument refs: #{orphans}"
            tests_failed += 1
          end

          # Test 6: Verify all entries have measures
          entries_without_measures = @db.get_first_value(<<~SQL)
            SELECT COUNT(*) FROM sanction_entries e
            LEFT JOIN entry_measures em ON e.id = em.entry_id
            WHERE em.id IS NULL
          SQL
          if entries_without_measures.zero?
            puts "[PASS] Test 6 - Entries without measures: #{entries_without_measures}"
            tests_passed += 1
          else
            puts "[FAIL] Test 6 - Entries without measures: #{entries_without_measures}"
            tests_failed += 1
          end

          # Summary
          puts "\n=== Summary ==="
          puts "Passed: #{tests_passed}, Failed: #{tests_failed}"

          tests_failed.zero?
        end
        # rubocop:enable Metrics/MethodLength

        # Get entity count
        # @return [Integer] Number of entities
        def entity_count
          return 0 unless @db

          @db.get_first_value('SELECT COUNT(*) FROM entities')
        end

        # Get entry count
        # @return [Integer] Number of entries
        def entry_count
          return 0 unless @db

          @db.get_first_value('SELECT COUNT(*) FROM sanction_entries')
        end

        # Close the database connection
        # @return [void]
        def close
          @db&.close
          @db = nil
        end

        private

        # Create the database schema
        # rubocop:disable Metrics/MethodLength
        def create_schema
          @db.execute_batch(<<~SQL)
            -- Entities table
            CREATE TABLE entities (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL CHECK(type IN ('person', 'organization', 'vessel', 'aircraft')),
                english_name TEXT,
                chinese_name TEXT,
                country_of_registration TEXT,
                nationality TEXT,
                date_of_birth TEXT,
                gender TEXT,
                title TEXT,
                remarks TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            -- Entity names (one-to-many)
            CREATE TABLE entity_names (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entity_id TEXT NOT NULL,
                english TEXT,
                chinese TEXT,
                is_primary INTEGER DEFAULT 0,
                FOREIGN KEY (entity_id) REFERENCES entities(id)
            );

            -- Announcements table
            CREATE TABLE announcements (
                id TEXT PRIMARY KEY,
                number TEXT NOT NULL,
                title TEXT,
                date TEXT,
                effective_date TEXT,
                issuing_authority TEXT,
                department TEXT,
                source_url TEXT,
                list_type TEXT CHECK(list_type IN ('anti_sanctions', 'unreliable_entity', 'export_control')),
                reason TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            -- Legal instruments table
            CREATE TABLE legal_instruments (
                id TEXT PRIMARY KEY,
                name_chinese TEXT NOT NULL,
                name_english TEXT,
                short_name TEXT,
                enacted_date TEXT,
                amended_date TEXT,
                url TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            -- Sanction entries table
            CREATE TABLE sanction_entries (
                id TEXT PRIMARY KEY,
                entity_id TEXT NOT NULL,
                announcement_id TEXT NOT NULL,
                status TEXT DEFAULT 'active' CHECK(status IN ('active', 'suspended', 'terminated', 'delisted')),
                listed_date TEXT,
                delisted_date TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (entity_id) REFERENCES entities(id),
                FOREIGN KEY (announcement_id) REFERENCES announcements(id)
            );

            -- Entry-LegalInstrument junction table (many-to-many)
            CREATE TABLE entry_legal_instruments (
                entry_id TEXT NOT NULL,
                legal_instrument_id TEXT NOT NULL,
                PRIMARY KEY (entry_id, legal_instrument_id),
                FOREIGN KEY (entry_id) REFERENCES sanction_entries(id),
                FOREIGN KEY (legal_instrument_id) REFERENCES legal_instruments(id)
            );

            -- Entry measures table (one-to-many)
            CREATE TABLE entry_measures (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_id TEXT NOT NULL,
                measure TEXT NOT NULL,
                FOREIGN KEY (entry_id) REFERENCES sanction_entries(id)
            );

            -- Announcement measures table (one-to-many)
            CREATE TABLE announcement_measures (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                announcement_id TEXT NOT NULL,
                measure TEXT NOT NULL,
                FOREIGN KEY (announcement_id) REFERENCES announcements(id)
            );

            -- Indexes
            CREATE INDEX idx_entities_type ON entities(type);
            CREATE INDEX idx_entities_country ON entities(country_of_registration);
            CREATE INDEX idx_entries_entity ON sanction_entries(entity_id);
            CREATE INDEX idx_entries_announcement ON sanction_entries(announcement_id);
            CREATE INDEX idx_entries_status ON sanction_entries(status);
            CREATE INDEX idx_announcements_list_type ON announcements(list_type);
            CREATE INDEX idx_announcements_date ON announcements(date);
          SQL
        end
        # rubocop:enable Metrics/MethodLength

        # Load legal instruments from directory
        # @param dir [String] Path to legal_instruments directory
        def load_legal_instruments(dir)
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, '*.yaml')).each do |file|
            data = YAML.load_file(file)
            @db.execute(
              'INSERT INTO legal_instruments (id, name_chinese, name_english, short_name, enacted_date, amended_date, url) VALUES (?, ?, ?, ?, ?, ?, ?)',
              [data['id'], data['name_chinese'], data['name_english'],
               data['short_name'], data['enacted_date'], data['amended_date'], data['url']]
            )
          end
          count = @db.get_first_value('SELECT COUNT(*) FROM legal_instruments')
          puts "  Loaded #{count} legal instruments"
        end

        # Load announcements from directory
        # @param dir [String] Path to announcements directory
        def load_announcements(dir)
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, '*.yaml')).each do |file|
            data = YAML.load_file(file)
            @db.execute(
              'INSERT INTO announcements (id, number, title, date, effective_date, issuing_authority, department, source_url, list_type, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [data['id'], data['number'], data['title'], data['date'],
               data['effective_date'], data['issuing_authority'], data['department'],
               data['source_url'], data['list_type'], data['reason']]
            )
            # Load measures
            (data['measures'] || []).each do |measure|
              @db.execute('INSERT INTO announcement_measures (announcement_id, measure) VALUES (?, ?)', [data['id'], measure])
            end
          end
          count = @db.get_first_value('SELECT COUNT(*) FROM announcements')
          puts "  Loaded #{count} announcements"
        end

        # Load entities from directory
        # @param dir [String] Path to entities directory
        def load_entities(dir)
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, '*.yaml')).each do |file|
            data = YAML.load_file(file)
            # Get primary name
            primary_name = (data['names'] || []).find { |n| n['is_primary'] } || data['names']&.first || {}

            @db.execute(
              'INSERT INTO entities ' \
              '(id, type, english_name, chinese_name, country_of_registration, ' \
              'nationality, date_of_birth, gender, title, remarks) ' \
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [data['id'], data['type'], primary_name['english'], primary_name['chinese'],
               data.dig('organization_details', 'country_of_registration'),
               data.dig('person_details', 'nationality'),
               data.dig('person_details', 'date_of_birth'),
               data.dig('person_details', 'gender'),
               data.dig('person_details', 'title'),
               data['remarks']]
            )
            # Load all names
            (data['names'] || []).each do |name|
              @db.execute(
                'INSERT INTO entity_names (entity_id, english, chinese, is_primary) VALUES (?, ?, ?, ?)',
                [data['id'], name['english'], name['chinese'], name['is_primary'] ? 1 : 0]
              )
            end
          end
          count = @db.get_first_value('SELECT COUNT(*) FROM entities')
          puts "  Loaded #{count} entities"
        end

        # Load entries from directory
        # @param dir [String] Path to entries directory
        def load_entries(dir)
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, '*.yaml')).each do |file|
            data = YAML.load_file(file)
            @db.execute(
              'INSERT INTO sanction_entries (id, entity_id, announcement_id, status, listed_date, delisted_date) VALUES (?, ?, ?, ?, ?, ?)',
              [data['id'], data['entity_id'], data['announcement_id'],
               data['status'], data['listed_date'], data['delisted_date']]
            )
            # Load legal instrument references
            (data['legal_instrument_ids'] || []).each do |li_id|
              @db.execute(
                'INSERT INTO entry_legal_instruments (entry_id, legal_instrument_id) VALUES (?, ?)',
                [data['id'], li_id]
              )
            end
            # Load measures
            (data['measures'] || []).each do |measure|
              @db.execute('INSERT INTO entry_measures (entry_id, measure) VALUES (?, ?)', [data['id'], measure])
            end
          end
          count = @db.get_first_value('SELECT COUNT(*) FROM sanction_entries')
          puts "  Loaded #{count} sanction entries"
        end
      end
    end
  end
end
