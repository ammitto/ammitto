# frozen_string_literal: true

require 'lutaml/model'
require 'roo'
require_relative 'entity'

module Ammitto
  module Data
    module Japan
      module METI
        # ForeignUserList represents the METI Foreign User List (外国ユーザーリスト)
        #
        # This list contains organizations that may be involved in WMD proliferation.
        # It is maintained by Japan's Ministry of Economy, Trade and Industry (METI)
        # under the Foreign Exchange and Foreign Trade Act (FEFTA).
        #
        # The list is published as an Excel file and updated periodically.
        #
        # @example Loading from Excel file
        #   list = Ammitto::Data::Japan::METI::ForeignUserList.from_xlsx('path/to/file.xlsx')
        #   puts "Loaded #{list.entities.count} entities"
        #
        # @example Iterating over entities
        #   list.entities.each do |entity|
        #     puts "#{entity.id}: #{entity.primary_name} (#{entity.country_code})"
        #   end
        #
        class ForeignUserList < Lutaml::Model::Serializable
          attribute :entities, Entity, collection: true
          attribute :source_file, :string
          attribute :source_url, :string
          attribute :list_date, :string
          attribute :fetched_at, :string

          xml do
            root 'ForeignUserList'
            map_element 'Entity', to: :entities
            map_element 'SourceFile', to: :source_file
            map_element 'SourceURL', to: :source_url
            map_element 'ListDate', to: :list_date
            map_element 'FetchedAt', to: :fetched_at
          end

          # Load Foreign User List from Excel file
          #
          # @param xlsx_path [String] path to the Excel file
          # @param source_url [String, nil] URL where the file was downloaded from
          # @return [ForeignUserList] the loaded list
          #
          # @example
          #   list = ForeignUserList.from_xlsx('20250929_4.xlsx', source_url: 'https://...')
          #
          def self.from_xlsx(xlsx_path, source_url: nil)
            workbook = Roo::Excelx.new(xlsx_path)
            workbook.default_sheet = workbook.sheets.first

            # Extract date from filename
            list_date = extract_date_from_filename(xlsx_path)
            source_file = File.basename(xlsx_path)

            entities = []

            # Skip header row (row 1)
            (2..workbook.last_row).each do |row_num|
              entity = parse_row(workbook, row_num, source_file, source_url, list_date)
              entities << entity if entity
            end

            new(
              entities: entities.compact,
              source_file: source_file,
              source_url: source_url,
              list_date: list_date,
              fetched_at: Time.now.utc.iso8601
            )
          end

          # Parse a single row from the Excel file
          #
          # @param workbook [Roo::Excelx] the workbook
          # @param row_num [Integer] the row number
          # @param source_file [String] source file name
          # @param source_url [String, nil] source URL
          # @param list_date [String] list date
          # @return [Entity, nil] the parsed entity or nil if invalid
          #
          def self.parse_row(workbook, row_num, source_file, source_url, list_date)
            row = workbook.row(row_num)

            # Column structure:
            # 1: No. (ID number)
            # 2: Country (Japanese\nEnglish)
            # 3: Company name
            # 4: Aliases (・Name1\n・Name2...)
            # 5: WMD type (Japanese\nCodes like B,C,M,N)
            # 6: Conventional weapons (optional)

            id_num = row[0]
            country_raw = row[1]
            company = row[2]
            aliases_raw = row[3]
            wmd_raw = row[4]
            cw_raw = row[5]

            return nil if id_num.nil? || company.nil? || company.to_s.strip.empty?

            # Parse country
            country = parse_bilingual_text(country_raw)

            # Parse company name
            company_name = parse_company_name(company)

            # Parse aliases
            aliases = parse_aliases(aliases_raw)

            # Parse WMD types
            wmd_codes = extract_wmd_codes(wmd_raw, cw_raw)

            # Get country code
            country_code = lookup_country_code(country[:ja], country[:en])

            # Build entity with proper ID
            Entity.new(
              id: "jp.meti.ful.#{id_num.to_i}",
              name_en: company_name[:en],
              name_ja: company_name[:ja],
              country_code: country_code,
              country_ja: country[:ja],
              country_en: country[:en],
              wmd_types: wmd_codes,
              aliases: aliases,
              entity_type: 'organization',
              source_file: source_file,
              source_url: source_url,
              list_date: list_date,
              row_number: id_num.to_i
            )
          end

          # Extract date from filename (format: YYYYMMDD_x.xlsx)
          # @param filename [String] the filename
          # @return [String] the date in YYYY-MM-DD format
          def self.extract_date_from_filename(filename)
            match = File.basename(filename).match(/(\d{8})/)
            return Date.today.to_s unless match

            "#{match[1][0, 4]}-#{match[1][4, 2]}-#{match[1][6, 2]}"
          end

          # Parse bilingual text (Japanese\nEnglish)
          # @param text [String, nil] the text to parse
          # @return [Hash] { ja:, en: }
          def self.parse_bilingual_text(text)
            return { ja: nil, en: nil } unless text

            parts = text.to_s.split("\n").map(&:strip).reject(&:empty?)

            if parts.length >= 2
              { ja: parts[0], en: parts[1] }
            elsif parts.length == 1
              if parts[0].match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
                { ja: parts[0], en: nil }
              else
                { ja: nil, en: parts[0] }
              end
            else
              { ja: nil, en: nil }
            end
          end

          # Parse company name
          # @param text [String, nil] the company name
          # @return [Hash] { ja:, en: }
          def self.parse_company_name(text)
            return { ja: nil, en: nil } unless text

            name = text.to_s.strip

            if name.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/) && name.match?(/[A-Za-z]/)
              # Mixed Japanese and English - treat as English for now
              { ja: nil, en: name }
            elsif name.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
              { ja: name, en: nil }
            else
              { ja: nil, en: name }
            end
          end

          # Parse aliases (・Name1\n・Name2...)
          # @param text [String, nil] the aliases text
          # @return [Array<String>] array of aliases
          def self.parse_aliases(text)
            return [] unless text

            text.to_s.split("\n").map do |line|
              cleaned = line.strip.sub(/^[・•\-*]\s*/, '').strip
              cleaned unless cleaned.empty?
            end.compact
          end

          # Extract WMD codes from WMD columns
          # @param wmd_raw [String, nil] the WMD type column
          # @param cw_raw [String, nil] the conventional weapons column
          # @return [Array<String>] array of WMD codes
          def self.extract_wmd_codes(wmd_raw, cw_raw)
            codes = []

            if wmd_raw
              # Normalize fullwidth to halfwidth characters
              normalized = wmd_raw.to_s.chars.map do |c|
                if c.match?(/[Ａ-Ｚａ-ｚ０-９]/)
                  (c.ord - 0xFEE0).chr
                else
                  c
                end
              end.join.upcase
              normalized.scan(/[BCMN]/).each { |code| codes << code unless codes.include?(code) }
            end

            if cw_raw
              normalized_cw = cw_raw.to_s.chars.map do |c|
                if c.match?(/[Ａ-Ｚａ-ｚ０-９]/)
                  (c.ord - 0xFEE0).chr
                else
                  c
                end
              end.join.upcase
              normalized_cw.scan('CW').each { |code| codes << code unless codes.include?(code) }
            end

            codes.uniq
          end

          # ISO 3166-1 alpha-2 country code lookup
          # @param ja_name [String, nil] Japanese country name
          # @param en_name [String, nil] English country name
          # @return [String, nil] the country code or nil
          def self.lookup_country_code(ja_name, en_name)
            # Japanese name mappings
            country_codes = {
              'アフガニスタン' => 'AF',
              'アラブ首長国連邦' => 'AE',
              'アルジェリア' => 'DZ',
              'アルメニア' => 'AM',
              'アンゴラ' => 'AO',
              'アルゼンチン' => 'AR',
              'オーストリア' => 'AT',
              'アゼルバイジャン' => 'AZ',
              'バングラデシュ' => 'BD',
              'ベラルーシ' => 'BY',
              'ベルギー' => 'BE',
              'ボスニア・ヘルツェゴビナ' => 'BA',
              'ブラジル' => 'BR',
              'ブルガリア' => 'BG',
              'カンボジア' => 'KH',
              'カナダ' => 'CA',
              'チリ' => 'CL',
              '中国' => 'CN',
              'コロンビア' => 'CO',
              'クロアチア' => 'HR',
              'キプロス' => 'CY',
              'チェコ' => 'CZ',
              'デンマーク' => 'DK',
              'エジプト' => 'EG',
              'エストニア' => 'EE',
              'フィンランド' => 'FI',
              'フランス' => 'FR',
              'ジョージア' => 'GE',
              'ドイツ' => 'DE',
              'ギリシャ' => 'GR',
              '香港' => 'HK',
              'ハンガリー' => 'HU',
              'アイスランド' => 'IS',
              'インド' => 'IN',
              'インドネシア' => 'ID',
              'イラン' => 'IR',
              'イラク' => 'IQ',
              'アイルランド' => 'IE',
              'イスラエル' => 'IL',
              'イタリア' => 'IT',
              '日本' => 'JP',
              'ヨルダン' => 'JO',
              'カザフスタン' => 'KZ',
              'ケニア' => 'KE',
              '大韓民国' => 'KR',
              'クウェート' => 'KW',
              'キルギス' => 'KG',
              'ラトビア' => 'LV',
              'レバノン' => 'LB',
              'リビア' => 'LY',
              'リトアニア' => 'LT',
              'ルクセンブルク' => 'LU',
              'マケドニア' => 'MK',
              'マレーシア' => 'MY',
              'メキシコ' => 'MX',
              'モルドバ' => 'MD',
              'モンゴル' => 'MN',
              'モンテネグロ' => 'ME',
              'モロッコ' => 'MA',
              'ミャンマー' => 'MM',
              'オランダ' => 'NL',
              'ナイジェリア' => 'NG',
              '北朝鮮' => 'KP',
              'ノルウェー' => 'NO',
              'パキスタン' => 'PK',
              'パレスチナ' => 'PS',
              'パナマ' => 'PA',
              'ペルー' => 'PE',
              'フィリピン' => 'PH',
              'ポーランド' => 'PL',
              'ポルトガル' => 'PT',
              'カタール' => 'QA',
              'ルーマニア' => 'RO',
              'ロシア' => 'RU',
              'サウジアラビア' => 'SA',
              'セルビア' => 'RS',
              'シンガポール' => 'SG',
              'スロバキア' => 'SK',
              'スロベニア' => 'SI',
              '南アフリカ' => 'ZA',
              'スペイン' => 'ES',
              'スーダン' => 'SD',
              'スウェーデン' => 'SE',
              'スイス' => 'CH',
              'シリア' => 'SY',
              '台湾' => 'TW',
              'タジキスタン' => 'TJ',
              'タンザニア' => 'TZ',
              'タイ' => 'TH',
              'チュニジア' => 'TN',
              'トルコ' => 'TR',
              'トルクメニスタン' => 'TM',
              'ウガンダ' => 'UG',
              'ウクライナ' => 'UA',
              'イギリス' => 'GB',
              'アメリカ' => 'US',
              'ウズベキスタン' => 'UZ',
              'ベネズエラ' => 'VE',
              'ベトナム' => 'VN',
              'イエメン' => 'YE',
              'ザンビア' => 'ZM',
              'ジンバブエ' => 'ZW'
            }

            # Try Japanese name
            if ja_name
              return country_codes[ja_name] if country_codes[ja_name]

              # Try partial match
              country_codes.each do |name, code|
                return code if ja_name.include?(name) || name.include?(ja_name)
              end
            end

            # Try English name
            if en_name
              en_lower = en_name.downcase
              country_codes.each_value do |code|
                case code
                when 'AF' then return 'AF' if en_lower.include?('afghanistan')
                when 'AE' then return 'AE' if en_lower.include?('arab emirates') || en_lower.include?('uae')
                when 'CN' then return 'CN' if en_lower.include?('china') && !en_lower.include?('taiwan')
                when 'HK' then return 'HK' if en_lower.include?('hong kong')
                when 'KP' then return 'KP' if en_lower.include?('north korea') || en_lower.include?("democratic people's")
                when 'KR' then return 'KR' if en_lower.include?('korea') && !en_lower.include?('north')
                when 'IR' then return 'IR' if en_lower.include?('iran')
                when 'IQ' then return 'IQ' if en_lower.include?('iraq')
                when 'RU' then return 'RU' if en_lower.include?('russia')
                when 'SY' then return 'SY' if en_lower.include?('syria')
                when 'TW' then return 'TW' if en_lower.include?('taiwan')
                end
              end
            end

            nil
          end

          # Get all entities
          # @return [Array<Entity>]
          def all_entities
            entities
          end

          # Get count of entities
          # @return [Integer]
          def count
            entities.length
          end

          # Find entity by ID
          # @param id [String] the entity ID
          # @return [Entity, nil]
          def find_by_id(id)
            entities.find { |e| e.id == id }
          end

          # Find entities by country code
          # @param country_code [String] the country code
          # @return [Array<Entity>]
          def find_by_country(country_code)
            entities.select { |e| e.country_code == country_code }
          end

          # Find entities by WMD type
          # @param wmd_type [String] the WMD type code
          # @return [Array<Entity>]
          def find_by_wmd_type(wmd_type)
            entities.select { |e| e.wmd_types.include?(wmd_type) }
          end

          # Convert to hash for YAML serialization
          # @return [Hash]
          def to_hash
            {
              'source_file' => source_file,
              'source_url' => source_url,
              'list_date' => list_date,
              'fetched_at' => fetched_at,
              'entities' => entities.map(&:to_hash)
            }
          end
        end
      end
    end
  end
end
