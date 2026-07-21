# frozen_string_literal: true

require 'lutaml/model'
require 'roo'
require 'yaml'
require 'fileutils'
require_relative 'entity'
require_relative 'announcement'
require_relative 'field_mapping'

module Ammitto
  module Data
    module Japan
      module Mof
        # Container for MOF sanctions list with announcement metadata and entities
        #
        # Represents a complete sanctions list from Japan MOF, including
        # announcement metadata and all affected entities.
        #
        # @example Load from YAML
        #   list = List.from_yaml_file(yaml_content)
        #   list.announcement.title # => { "ja" => "ロシア連邦(個人)", "en" => "Russian Federation (Individuals)" }
        #   list.entities.count # => 1500
        #   list.entities.first.name # => { "ja" => "プーチン", "en" => "PUTIN" }
        #
        # @example Parse from Excel
        #   list = List.from_xlsx(path, source_url: 'https://...')
        #   list.entities.count # => 1500
        #
        class List < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :announcement, Announcement
          attribute :entities, Entity, collection: true
          attribute :instruments, :string, collection: true

          yaml do
            root 'sanction_list'
            map 'id', to: :id
            map 'announcement', to: :announcement
            map 'instruments', to: :instruments
          end

          # Create from standard YAML file format
          # @param yaml_content [String] YAML content
          # @return [List]
          def self.from_yaml_file(yaml_content)
            data = YAML.safe_load(yaml_content, permitted_classes: [Date, Time], aliases: true)

            # Handle the standard announcement format
            if data['announcement'] && data['sanction_details']
              from_announcement_format(data)
            else
              from_yaml(yaml_content)
            end
          end

          # Create from announcement format (sanction_details)
          # @param data [Hash] Parsed YAML data
          # @return [List]
          def self.from_announcement_format(data)
            list = new(
              id: data['id']
            )

            # Build announcement
            ann_data = data['announcement']
            if ann_data
              list.announcement = Announcement.new

              # Handle title (can be array of { lang => value } or single hash)
              if ann_data['title'].is_a?(Array)
                ann_data['title'].each do |title_item|
                  title_item.each do |lang, value|
                    list.announcement.add_title(lang, value)
                  end
                end
              elsif ann_data['title'].is_a?(Hash)
                ann_data['title'].each do |lang, value|
                  list.announcement.add_title(lang, value)
                end
              end

              list.announcement.url = ann_data['url']
              list.announcement.source_url = ann_data['source_url']
              list.announcement.source_file = ann_data['source_file']
              list.announcement.authority = ann_data['authority']
              list.announcement.publisher = ann_data['publisher']
              list.announcement.type = ann_data['type']

              # Parse date
              list.announcement.publish_date = parse_date(ann_data['publish_date']) if ann_data['publish_date']
            end

            # Build instruments
            list.instruments = data.dig('sanction_details', 'instruments')&.map do |inst|
              inst.is_a?(Hash) ? inst['id'] : inst
            end || []

            # Build entities from sanction_details
            entities_data = data.dig('sanction_details', 'entities') || []
            list.entities = entities_data.map do |entity_data|
              build_entity(entity_data)
            end

            list
          end

          # Build entity from hash data
          # @param data [Hash] Entity data
          # @return [Entity]
          def self.build_entity(data)
            entity = Entity.new(
              id: data['id'],
              type: data['type'],
              effective_date: parse_date(data['effective_date']),
              sanction_list: data['sanction_list'],
              sanction_list_en: data['sanction_list_en'],
              country: data['country'],
              address: data['address'],
              date_of_birth: data['date_of_birth'],
              place_of_birth: data['place_of_birth'],
              nationality: data['nationality'],
              list_date: data['list_date'],
              source_url: data['source_url'],
              un_designation_date: data['un_designation_date']
            )

            # Add name
            if data['name'].is_a?(Hash)
              data['name'].each do |lang, value|
                entity.add_name(lang, value)
              end
            end

            # Add title
            if data['title'].is_a?(Hash)
              data['title'].each do |lang, value|
                entity.add_title(lang, value)
              end
            end

            # Add aliases
            Array(data['aliases']).each do |alias_name|
              entity.add_alias(alias_name)
            end

            # Add measures
            Array(data['measures']).each do |measure_data|
              types = measure_data['type']
              ja = measure_data['ja']
              en = measure_data['en']
              entity.add_measure(types: types, ja: ja, en: en)
            end

            # Add reasons
            Array(data['reason']).each do |reason_data|
              entity.add_reason(ja: reason_data['ja'], en: reason_data['en']) if reason_data.is_a?(Hash)
            end

            # Add remarks
            Array(data['remarks']).each do |remark_data|
              entity.add_remark(ja: remark_data['ja'], en: remark_data['en']) if remark_data.is_a?(Hash)
            end

            # Add phones
            Array(data['phones']).each { |p| entity.add_phone(p) }

            # Add fax
            Array(data['fax']).each { |f| entity.add_fax(f) }

            # Add identification
            if data['identification'].is_a?(Hash)
              data['identification'].each do |id_type, number|
                entity.add_identifier(id_type, number)
              end
            end

            entity
          end

          # Parse date from various formats
          # @param value [String, Date, nil] Date value
          # @return [Date, nil]
          def self.parse_date(value)
            return nil if value.nil?
            return value if value.is_a?(Date)

            Date.parse(value.to_s)
          rescue Date::Error
            nil
          end

          # Parse from Excel file
          # @param xlsx_path [String] Path to Excel file
          # @param source_url [String] Source URL for the data
          # @param list_id [String, nil] Specific list ID to parse
          # @return [Array<List>] List of parsed sanction lists
          def self.from_xlsx(xlsx_path, source_url:, list_id: nil)
            xlsx = Roo::Spreadsheet.open(xlsx_path)
            lists = []
            entity_counter = 0

            # Parse each sheet
            xlsx.sheets.each do |sheet_name|
              next if should_skip_sheet?(sheet_name)

              # Get list config for this sheet
              config = Mof::SANCTION_LIST_CONFIG[sheet_name.strip]
              next unless config

              # Skip if we're filtering by list_id and this isn't the one
              next if list_id && config[:id] != list_id

              # Parse the sheet
              entities = parse_sheet(xlsx, sheet_name, config, source_url, entity_counter)
              entity_counter += entities.size

              next if entities.empty?

              # Create list with announcement
              list = new(
                id: config[:id],
                instruments: [
                  'jp/diet-foreign-exchange-and-foreign-trade-act',
                  'jp/cabinet-order-foreign-exchange'
                ]
              )

              # Build announcement
              list.announcement = build_announcement(sheet_name, config, source_url, xlsx_path)

              list.entities = entities
              lists << list
            end

            lists
          end

          # Check if sheet should be skipped
          def self.should_skip_sheet?(sheet_name)
            skip_sheets = ['一覧']
            return true if skip_sheets.include?(sheet_name)

            # Skip repealed sheets
            sheet_name.match?(/【.*廃止.*】|解除/)
          end

          # Parse a single sheet
          def self.parse_sheet(xlsx, sheet_name, config, _source_url, _entity_counter)
            xlsx.sheet(sheet_name)

            first_row = xlsx.first_row
            last_row = xlsx.last_row
            first_col = xlsx.first_column
            last_col = xlsx.last_column

            return [] unless first_row && last_row && first_row < last_row

            header_row = find_header_row(xlsx, first_row, last_row, first_col)
            headers = extract_headers(xlsx, header_row, first_col, last_col)

            entity_type = FieldMapping.determine_entity_type(sheet_name)
            entities = []
            counter = 0

            (header_row + 1).upto(last_row).each do |row|
              entity = parse_row(xlsx, row, headers, entity_type, config, first_col, counter)
              if entity
                entities << entity
                counter += 1
              end
            end

            entities
          end

          # Find header row
          def self.find_header_row(xlsx, first_row, last_row, first_col)
            first_row.upto([first_row + 5, last_row].min) do |row|
              val = xlsx.cell(row, first_col).to_s
              clean_val = val.gsub(/<[^>]+>/, '').gsub(/[\s\u3000]/, '')
              return row if clean_val.include?('告示日付')
            end
            first_row + 1
          end

          # Extract headers
          def self.extract_headers(xlsx, header_row, first_col, last_col)
            headers = []
            first_col.upto(last_col).each do |col|
              val = xlsx.cell(header_row, col).to_s
              val = val.gsub(/<[^>]+>/, '').gsub(/[\s\u3000]+/, ' ').strip
              headers << (val.empty? ? nil : val)
            end
            headers
          end

          # Parse a row
          def self.parse_row(xlsx, row, headers, entity_type, config, first_col, counter)
            entity = Entity.new(
              type: entity_type == :organization ? 'organization' : 'individual',
              sanction_list: config[:id],
              sanction_list_en: Mof::SANCTION_LIST_NAMES_EN[config[:id]]
            )

            has_data = false
            gazette_date = nil
            gazette_number = nil
            has_individual_fields = false

            headers.each_with_index do |header, col_idx|
              next if header.nil?

              col = first_col + col_idx
              value = xlsx.cell(row, col)
              next if value.nil?

              value_str = clean_value(value)
              next if value_str.empty?

              has_data = true
              has_individual_fields = true if header.include?('生年月日')

              # Apply field mapping
              result = apply_field_mapping(entity, header, value_str, sheet_name: config[:slug])
              if result.is_a?(Hash)
                gazette_date ||= result[:date]
                gazette_number ||= result[:number]
              elsif result.is_a?(String)
                gazette_date ||= result
              end
            end

            return nil unless has_data && (entity.name['ja'] || entity.name['en'])

            # Determine entity type for unknown sheets
            if entity_type == :unknown
              entity.type = has_individual_fields ? 'individual' : 'organization'
            end

            # Set effective_date
            entity.effective_date = parse_date(gazette_date) if gazette_date

            # Generate entity ID
            entity_number = (gazette_number || (counter + 1).to_s).gsub(/[*()（）]/, '')
            list_slug = config[:id].gsub('jp/mof-asset-freeze-', '')
            entity.id = "jp.mof.#{list_slug}.#{entity_number}"

            # Add default measure
            entity.add_measure(
              types: ['asset_freeze'],
              ja: '資産凍結の対象',
              en: 'Subject to asset freeze'
            )

            entity
          end

          # Clean cell value
          def self.clean_value(value)
            value.to_s.strip.gsub(/[\r\n]+/, ' ').gsub(/\s+/, ' ')
          end

          # Apply field mapping
          def self.apply_field_mapping(entity, header, value, sheet_name:)
            mapping = FieldMapping.get_mapping(sheet_name, header)

            if mapping
              # Create a simple parser object for date parsing
              parser = ->(v) { parse_list_date(v) }
              FieldMapping.apply_mapping(entity, mapping, value, parser)
            else
              # Add unmapped fields to reason
              entity.add_reason(ja: "#{header}: #{value}") unless value == '不明' || value.to_s.strip.empty?
              nil
            end
          end

          # Parse list date
          def self.parse_list_date(value)
            return nil if value.nil? || value.to_s.strip.empty?

            str = value.to_s.strip

            # Check if it's a pure number (Excel serial date)
            return excel_serial_to_date(str.to_i) if str.match?(/^\d+$/)

            # Try standard date formats
            parse_date(str) || str
          end

          # Convert Excel serial date to date string
          def self.excel_serial_to_date(serial)
            return nil if serial.nil? || serial <= 0

            excel_epoch = Date.new(1899, 12, 30)
            begin
              date = excel_epoch + serial
              date.strftime('%Y-%m-%d')
            rescue StandardError
              serial.to_s
            end
          end

          # Build announcement from sheet info
          def self.build_announcement(sheet_name, config, source_url, xlsx_path)
            announcement = Announcement.new(
              authority: 'jp/mof',
              publisher: 'jp/mof',
              type: 'jp/asset-freeze-announcement',
              source_file: File.basename(xlsx_path),
              source_url: source_url,
              url: Mof::INDEX_URL
            )

            # Add titles
            clean_name = sheet_name.gsub(/^[0-9]+\.\s*/, '')
            announcement.add_title('ja', clean_name)
            announcement.add_title('en', Mof::SANCTION_LIST_NAMES_EN[config[:id]] || clean_name)

            announcement
          end

          # Get entity count
          # @return [Integer]
          def entity_count
            entities.count
          end

          # Convert to hash for YAML serialization
          # @return [Hash]
          def to_hash
            {
              'announcement' => announcement&.to_hash,
              'sanction_details' => {
                'instruments' => instruments.map { |i| { 'id' => i } },
                'entities' => entities.map(&:to_hash)
              }
            }.compact
          end

          # Write to YAML file
          # @param output_dir [String] Output directory
          # @param date_str [String] Date string for filename (YYYYMMDD)
          # @return [String] Path to generated file
          def to_yaml_file(output_dir, date_str)
            FileUtils.mkdir_p(output_dir)

            # Get config for this list
            config = Mof::SANCTION_LIST_CONFIG.values.find { |c| c[:id] == id }

            if config
              dir_name = "#{config[:index].to_s.rjust(2, '0')}-#{config[:slug]}"
              list_dir = File.join(output_dir, dir_name)
              FileUtils.mkdir_p(list_dir)
              yaml_path = File.join(list_dir, "#{date_str}.yml")
            else
              yaml_path = File.join(output_dir, "#{date_str}_#{id.gsub('/', '_')}.yml")
            end

            # Generate YAML
            data = to_hash
            yaml_content = generate_yaml(yaml_path, data)

            File.write(yaml_path, yaml_content)
            yaml_path
          end

          # Generate YAML with proper schema reference
          def generate_yaml(yaml_path, data)
            depth = yaml_path.split('/').length - yaml_path.split('/').index { |p| p == 'sanction-lists' }.to_i - 2
            schema_path = "#{'../' * depth}schemas/jp-announcement.yml"
            header = "# yaml-language-server: $schema=#{schema_path}\n---\n"
            header + data.to_yaml(line_width: -1).gsub(/^---\n/, '')
          end
        end
      end
    end
  end
end
