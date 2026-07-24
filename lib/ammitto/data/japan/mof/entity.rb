# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module Japan
      module Mof
        # Represents a sanctioned entity from Japan MOF Asset Freeze List
        #
        # Entity can be either an individual or organization with multilingual
        # names, sanctions measures, and related metadata.
        #
        # @example Creating an entity from parsed data
        #   entity = Entity.new(
        #     id: 'jp.mof.russia-individuals.1',
        #     type: 'individual',
        #     name: { ja: 'プーチン', en: 'PUTIN' },
        #     sanction_list: 'jp/mof-asset-freeze-russia-individuals'
        #   )
        #
        class Entity < Lutaml::Model::Serializable
          # Sanction measure
          class Measure < Lutaml::Model::Serializable
            attribute :type, :string, collection: true
            attribute :ja, :string
            attribute :en, :string

            yaml do
              map 'type', to: :type
              map 'ja', to: :ja
              map 'en', to: :en
            end
          end

          # Multilingual text (for reason, remarks)
          class MultilingualText < Lutaml::Model::Serializable
            attribute :ja, :string
            attribute :en, :string

            yaml do
              map 'ja', to: :ja
              map 'en', to: :en
            end
          end

          # Entity types
          TYPES = %w[individual organization vessel aircraft].freeze

          # Required fields
          attribute :id, :string
          attribute :type, :string
          attribute :name, :hash
          attribute :effective_date, :date
          attribute :sanction_list, :string

          # Optional fields
          attribute :sanction_list_en, :string
          attribute :country, :string
          attribute :address, :string

          # Individual-specific
          attribute :date_of_birth, :string
          attribute :place_of_birth, :string
          attribute :nationality, :string
          attribute :title, :hash

          # Sanctions
          attribute :measures, Measure, collection: true
          attribute :reason, MultilingualText, collection: true
          attribute :remarks, MultilingualText, collection: true
          attribute :aliases, :string, collection: true

          # Contact info
          attribute :phones, :string, collection: true
          attribute :fax, :string, collection: true

          # Identification
          attribute :identification, :hash

          # Dates
          attribute :list_date, :string
          attribute :un_designation_date, :string

          # Source
          attribute :source_url, :string

          yaml do
            map 'id', to: :id
            map 'name', to: :name
            map 'type', to: :type
            map 'effective_date', to: :effective_date
            map 'sanction_list', to: :sanction_list
            map 'sanction_list_en', to: :sanction_list_en
            map 'country', to: :country
            map 'address', to: :address
            map 'date_of_birth', to: :date_of_birth
            map 'place_of_birth', to: :place_of_birth
            map 'nationality', to: :nationality
            map 'title', to: :title
            map 'measures', to: :measures
            map 'reason', to: :reason
            map 'remarks', to: :remarks
            map 'aliases', to: :aliases
            map 'phones', to: :phones
            map 'fax', to: :fax
            map 'identification', to: :identification
            map 'list_date', to: :list_date
            map 'un_designation_date', to: :un_designation_date
            map 'source_url', to: :source_url
          end

          # Check if this is an individual
          # @return [Boolean]
          def individual?
            type == 'individual'
          end

          # Check if this is an organization
          # @return [Boolean]
          def organization?
            type == 'organization'
          end

          # Get primary name
          # @param lang [String] Language code (ja, en)
          # @return [String, nil]
          def primary_name(lang = nil)
            if lang
              name[lang]
            else
              name['ja'] || name['en']
            end
          end

          # Add a name in a specific language
          # @param lang [String] Language code
          # @param value [String] Name value
          def add_name(lang, value)
            return if value.nil? || value.to_s.strip.empty?

            self.name ||= {}
            name[lang.to_s] = value.to_s.strip
          end

          # Add a measure
          # @param types [Array<String>] Measure types
          # @param ja [String, nil] Japanese description
          # @param en [String, nil] English description
          def add_measure(types:, ja: nil, en: nil)
            return if types.nil? || types.empty?

            measures << Measure.new(
              type: Array(types),
              ja: ja,
              en: en
            )
          end

          # Add a reason
          # @param ja [String, nil] Japanese text
          # @param en [String, nil] English text
          def add_reason(ja: nil, en: nil)
            return if ja.nil? && en.nil?

            reason << MultilingualText.new(ja: ja, en: en)
          end

          # Add a remark
          # @param ja [String, nil] Japanese text
          # @param en [String, nil] English text
          def add_remark(ja: nil, en: nil)
            return if ja.nil? && en.nil?

            remarks << MultilingualText.new(ja: ja, en: en)
          end

          # Add an alias
          # @param alias_name [String] Alias name
          def add_alias(alias_name)
            return if alias_name.nil? || alias_name.to_s.strip.empty?
            return if alias_name.to_s.strip == '不明'

            aliases << alias_name.to_s.strip unless aliases.include?(alias_name.to_s.strip)
          end

          # Add title in a specific language
          # @param lang [String] Language code
          # @param value [String] Title value
          def add_title(lang, value)
            return if value.nil? || value.to_s.strip.empty?
            return if value.to_s.strip == '不明'

            self.title ||= {}
            title[lang.to_s] = value.to_s.strip
          end

          # Add identification
          # @param id_type [String] ID type (passport, national_id, etc.)
          # @param number [String] ID number
          def add_identifier(id_type, number)
            return if number.nil? || number.to_s.strip.empty?
            return if number.to_s.strip == '不明'

            self.identification ||= {}
            key = case id_type
                  when 'passport' then 'passport'
                  when 'id', 'id-card' then 'national_id'
                  else 'other'
                  end
            identification[key] = number.to_s.strip
          end

          # Add phone number
          # @param number [String] Phone number
          def add_phone(number)
            return if number.nil? || number.to_s.strip.empty?
            return if number.to_s.strip == '不明'

            phones << number.to_s.strip unless phones.include?(number.to_s.strip)
          end

          # Add fax number
          # @param number [String] Fax number
          def add_fax(number)
            return if number.nil? || number.to_s.strip.empty?
            return if number.to_s.strip == '不明'

            fax << number.to_s.strip unless fax.include?(number.to_s.strip)
          end

          # Check if entity has minimum required data
          # @return [Boolean]
          def valid?
            name && (name['ja'] || name['en']) && type && sanction_list
          end

          # Convert to hash for YAML serialization (matches data-jp schema)
          # @return [Hash]
          def to_hash
            hash = {}

            # Required fields
            hash['id'] = id if id
            hash['name'] = compact_hash(name) if name&.any?
            hash['type'] = type if type
            hash['effective_date'] = effective_date&.to_s if effective_date
            hash['sanction_list'] = sanction_list if sanction_list

            # Optional fields
            hash['sanction_list_en'] = sanction_list_en if sanction_list_en && !sanction_list_en.empty?
            hash['country'] = country if country && !country.empty?
            hash['address'] = address if address && address != '不明'
            hash['title'] = compact_hash(title) if title&.any?
            hash['date_of_birth'] = date_of_birth if date_of_birth && !date_of_birth.empty?
            hash['place_of_birth'] = place_of_birth if place_of_birth && !place_of_birth.empty?
            hash['nationality'] = nationality if nationality && !nationality.empty?
            hash['list_date'] = list_date if list_date && !list_date.empty?
            hash['source_url'] = source_url if source_url

            # Array fields
            hash['aliases'] = aliases if aliases&.any?
            hash['reason'] = reason.map { |r| compact_hash({ ja: r.ja, en: r.en }) } if reason&.any?
            if measures&.any?
              hash['measures'] = measures.map do |m|
                h = { 'type' => m.type }
                h['ja'] = m.ja if m.ja
                h['en'] = m.en if m.en
                h
              end
            end
            hash['phones'] = phones if phones&.any?
            hash['fax'] = fax if fax&.any?

            # Identification
            hash['identification'] = compact_hash(identification) if identification&.any?

            # Remarks
            hash['remarks'] = remarks.map { |r| compact_hash({ ja: r.ja, en: r.en }) } if remarks&.any?

            # UN designation date
            hash['un_designation_date'] = un_designation_date if un_designation_date

            hash.compact
          end

          private

          # Compact hash by removing nil/empty values
          def compact_hash(hash)
            return nil unless hash.is_a?(Hash)

            result = hash.reject { |_, v| v.nil? || v.to_s.strip.empty? }
            result.empty? ? nil : result
          end
        end
      end
    end
  end
end
