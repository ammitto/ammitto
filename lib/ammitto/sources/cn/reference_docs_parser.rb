# frozen_string_literal: true

require 'date'
require 'nokogiri'
require 'fileutils'

module Ammitto
  module Sources
    module Cn
      # ReferenceDocsParser parses China sanctions from local reference documents
      #
      # Reads from local markdown files in data-cn/reference-docs/:
      # - unrealiable-entity-list/ (不可靠实体清单)
      # - import-export-control-list/ (出口管制管控名单)
      # - anti-sanction-list/ (反制裁清单)
      #
      # @example
      #   parser = Ammitto::Sources::Cn::ReferenceDocsParser.new('/path/to/reference-docs')
      #   entities = parser.parse_all
      #
      class ReferenceDocsParser
        # @return [String] path to reference docs directory
        attr_reader :docs_path

        # @return [Boolean] verbose mode
        attr_reader :verbose

        # List type mapping
        LIST_TYPES = {
          'unrealiable-entity-list' => 'unreliable_entity',
          'import-export-control-list' => 'export_control',
          'anti-sanction-list' => 'anti_sanctions'
        }.freeze

        # Measure patterns (Chinese -> English)
        MEASURE_PATTERNS = {
          '禁止从事与中国有关的进出口活动' => 'import_export_ban',
          '禁止在中国境内新增投资' => 'investment_ban',
          '禁止高级管理人员入境' => 'entry_ban',
          '不批准并取消高级管理人员工作许可' => 'work_permit_ban',
          '冻结.*财产' => 'asset_freeze',
          '禁止.*签证' => 'visa_ban',
          '不准入境' => 'entry_ban',
          '禁止出口.*两用物项' => 'dual_use_export_ban',
          '禁止转移或提供两用物项' => 'dual_use_transfer_ban',
          '禁止.*交易' => 'transaction_ban',
          '禁止向中国出口' => 'export_to_china_ban'
        }.freeze

        # Legal basis patterns
        LEGAL_BASIS = {
          '对外贸易法' => 'Foreign Trade Law of the PRC',
          '国家安全法' => 'National Security Law of the PRC',
          '反外国制裁法' => 'Anti-Foreign Sanctions Law of the PRC',
          '出口管制法' => 'Export Control Law of the PRC',
          '不可靠实体清单规定' => 'Unreliable Entity List Provisions',
          '两用物项出口管制条例' => 'Regulation on Export Control of Dual-Use Items'
        }.freeze

        # Initialize with path to reference docs
        # @param docs_path [String] path to reference-docs directory
        # @param verbose [Boolean] enable verbose output
        def initialize(docs_path, verbose: false)
          @docs_path = docs_path
          @verbose = verbose
        end

        # Parse all reference documents
        # @return [Hash] { announcements: [...], entities: [...] }
        def parse_all
          announcements = []
          entities = []

          LIST_TYPES.each do |dir_name, list_type|
            dir_path = File.join(docs_path, dir_name)
            next unless Dir.exist?(dir_path)

            puts "[CN ReferenceDocs] Parsing #{dir_name}..." if verbose

            Dir.glob(File.join(dir_path, '*.md')).each do |file|
              result = parse_file(file, list_type)
              if result
                announcements << result[:announcement]
                entities.concat(result[:entities])
              end
            end
          end

          puts "[CN ReferenceDocs] Parsed #{announcements.size} announcements, #{entities.size} entities" if verbose

          { announcements: announcements, entities: entities }
        end

        private

        # Parse a single markdown file
        # @param file [String] path to markdown file
        # @param list_type [Symbol] the list type
        # @return [Hash, nil] { announcement: Hash, entities: Array<Hash> }
        def parse_file(file, list_type)
          content = File.read(file, encoding: 'UTF-8')
          return nil if content.empty?

          # Extract URL from first line
          url = content.lines.first&.strip
          url = nil unless url&.start_with?('http')

          # Extract metadata
          metadata = extract_metadata(content)

          # Extract entities
          extracted_entities = extract_entities(content, list_type, metadata)

          # Extract measures
          measures = extract_measures(content)

          # Extract legal basis
          legal_basis = extract_legal_basis(content)

          # Build announcement
          announcement = {
            id: metadata[:announcement_number]&.gsub(/[^\w-]/, '-')&.downcase || File.basename(file, '.md'),
            number: metadata[:announcement_number],
            date: metadata[:date],
            title: metadata[:title],
            issuing_authority: metadata[:issuing_authority],
            list_type: list_type,
            legal_basis: legal_basis,
            measures: measures,
            source_url: url
          }

          # Build entities with announcement info
          entities = extracted_entities.map do |entity|
            entity.merge(
              list_type: list_type,
              announcement_number: metadata[:announcement_number],
              announcement_date: metadata[:date],
              measures: measures,
              legal_basis: legal_basis,
              source_url: url
            )
          end

          { announcement: announcement, entities: entities }
        end

        # Extract metadata from content
        # @param content [String] file content
        # @return [Hash] metadata
        def extract_metadata(content)
          metadata = {}

          # Extract title (first non-URL line that looks like a title)
          content.lines.each do |line|
            line = line.strip
            next if line.empty?
            next if line.start_with?('http')
            next if line.start_with?('【')

            # This should be the title
            metadata[:title] = line
            break
          end

          # Extract metadata fields
          metadata[:issuing_authority] = Regexp.last_match(1).strip if content =~ /【发布单位】(.+?)(?:\n|$)/

          metadata[:announcement_number] = Regexp.last_match(1).strip if content =~ /【发布文号】(.+?)(?:\n|$)/

          if content =~ /【发文日期】(.+?)(?:\n|$)/
            date_str = Regexp.last_match(1).strip
            metadata[:date] = parse_chinese_date(date_str)
          end

          # Also try to extract date from title or content
          if content =~ /(\d{4})年(\d{1,2})月(\d{1,2})日/
            metadata[:date] = Date.new(Regexp.last_match(1).to_i,
                                       Regexp.last_match(2).to_i,
                                       Regexp.last_match(3).to_i)
          end

          metadata
        end

        # Parse Chinese date format
        # @param date_str [String] date string like "2024年05月20日"
        # @return [Date, nil]
        def parse_chinese_date(date_str)
          return nil unless date_str

          if date_str =~ /(\d{4})年(\d{1,2})月(\d{1,2})日/
            Date.new(Regexp.last_match(1).to_i,
                     Regexp.last_match(2).to_i,
                     Regexp.last_match(3).to_i)
          end
        rescue ArgumentError
          nil
        end

        # Extract entities from content
        # @param content [String] file content
        # @param list_type [Symbol] the list type
        # @param metadata [Hash] metadata
        # @return [Array<Hash>] entities
        def extract_entities(content, _list_type, _metadata)
          entities = []

          # First, try to find the attachment section (附件)
          # This contains the properly formatted entity list
          attachment_content = extract_attachment_section(content)

          if attachment_content
            entities.concat(extract_organizations_from_attachment(attachment_content))
            entities.concat(extract_persons_from_attachment(attachment_content))
          end

          # If no attachment found, try to extract from body (fallback)
          if entities.empty?
            entities.concat(extract_organizations_from_body(content))
            entities.concat(extract_persons_from_body(content))
          end

          # Deduplicate by english_name or chinese_name
          entities.uniq { |e| e[:english_name] || e[:chinese_name] }
        end

        # Extract attachment section from content
        # @param content [String] file content
        # @return [String, nil] attachment content
        def extract_attachment_section(content)
          # Look for 附件 (Attachment) marker
          return Regexp.last_match(1) if content =~ /附件[：:\s]*(.+?)$/m

          nil
        end

        # Extract organizations from attachment section
        # @param content [String] attachment content
        # @return [Array<Hash>] organizations
        def extract_organizations_from_attachment(content)
          entities = []

          # Find organization section (一、企业 or similar)
          org_section = nil
          if content =~ /[一二三四五六七八九十]+[、．.]\s*企业(.+?)(?=[一二三四五六七八九十]+[、．.])/m
            org_section = Regexp.last_match(1)
          elsif content =~ /[一二三四五六七八九十]+[、．.]\s*企业(.+)$/m
            org_section = Regexp.last_match(1)
          end

          return entities unless org_section

          # Pattern: （一）Chinese Name (English Name)
          # or: 1. Chinese Name (English Name)
          org_pattern = /[（(][一二三四五六七八九十\d]+[）)]\s*([^\n（(]+?)（([^）)]+)）/

          org_section.scan(org_pattern) do |match|
            chinese_name = match[0].strip
            english_name = match[1].strip

            next if chinese_name.length < 2
            next if english_name.length < 2

            entities << {
              chinese_name: chinese_name,
              english_name: english_name,
              entity_type: 'organization',
              id: generate_entity_id(english_name)
            }
          end

          entities
        end

        # Extract persons from attachment section
        # @param content [String] attachment content
        # @return [Array<Hash>] persons
        def extract_persons_from_attachment(content)
          persons = []

          # Find person section (二、高级管理人员 or similar)
          person_section = nil
          person_section = Regexp.last_match(1) if content =~ /[一二三四五六七八九十]+[、．.]\s*(?:高级管理人员|个人|人员)(.+?)$/m

          return persons unless person_section

          # Pattern: （一）Chinese Name (English Name)，gender，title
          person_pattern = /[（(][一二三四五六七八九十\d]+[）)]\s*([^\n（(]+?)（([^）)]+)）[，,]\s*([男女])，\s*(.+)/

          person_section.scan(person_pattern) do |match|
            chinese_name = match[0].strip
            english_name = match[1].strip
            _gender = match[2]
            title = match[3].strip

            next if chinese_name.length < 2
            next if english_name.length < 2

            persons << {
              chinese_name: chinese_name,
              english_name: english_name,
              entity_type: 'person',
              title: title,
              id: generate_entity_id(english_name)
            }
          end

          persons
        end

        # Extract organizations from body text (fallback)
        # @param content [String] file content
        # @return [Array<Hash>] organizations
        def extract_organizations_from_body(content)
          entities = []

          # Pattern: Chinese name (English name) where English contains Corporation/Company/etc
          org_pattern = /([^\n（(]{3,}?)（([^）)]*(?:Corporation|Company|Inc|Ltd|LLC|GmbH|AG|Group|Systems|Technologies)[^）)]*)）/i

          content.scan(org_pattern) do |match|
            chinese_name = match[0].strip
            english_name = match[1].strip

            next if chinese_name.match?(/\d{4}年/)
            next if chinese_name.length < 2

            entities << {
              chinese_name: chinese_name,
              english_name: english_name,
              entity_type: 'organization',
              id: generate_entity_id(english_name)
            }
          end

          entities
        end

        # Extract persons from body text (fallback)
        # @param content [String] file content
        # @return [Array<Hash>] persons
        def extract_persons_from_body(content)
          persons = []

          # Pattern: Chinese name (English name)，gender，title
          # Using Regexp.new to avoid encoding issues with Chinese characters
          person_pattern = Regexp.new('([^\n（(]{2,10})（([^）)]+)）[，,]\\s*([男女])，')

          content.scan(person_pattern) do |match|
            chinese_name = match[0].strip
            english_name = match[1].strip

            next if chinese_name.match?(/\d{4}年/)
            next if english_name.match?(/公司|企业|集团/) # Skip if looks like organization

            persons << {
              chinese_name: chinese_name,
              english_name: english_name,
              entity_type: 'person',
              id: generate_entity_id(english_name)
            }
          end

          persons
        end

        # Extract measures from content
        # @param content [String] file content
        # @return [Array<String>] measures
        def extract_measures(content)
          measures = []

          MEASURE_PATTERNS.each do |chinese, english|
            measures << english if content.match?(/#{chinese}/)
          end

          measures.uniq
        end

        # Extract legal basis from content
        # @param content [String] file content
        # @return [Array<String>] legal basis
        def extract_legal_basis(content)
          basis = []

          LEGAL_BASIS.each do |chinese, english|
            basis << english if content.include?(chinese)
          end

          basis.uniq
        end

        # Generate entity ID from name
        # @param name [String]
        # @return [String]
        def generate_entity_id(name)
          slug = name
                 .to_s
                 .downcase
                 .gsub(/[^a-z0-9]+/, '-')
                 .gsub(/^-|-$/, '')
                 .slice(0, 50)

          "cn-#{slug}"
        end
      end
    end
  end
end
