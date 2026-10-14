# frozen_string_literal: true

# BaseTransformer is loaded by transformers/registry.rb
require_relative '../../parse_failure_visibility'
require_relative '../../utils/presence'

module Ammitto
  module Sources
    module Tr
      # Transformer for Turkey Sanctions data
      #
      # IRIs are minted from SanctionedEntity#local_id rather than from
      # +reference_number+ directly, for two independent reasons. Turkey
      # leaves the "Sıra No" column blank for part of List D, so a
      # sizeable minority of rows carry no number to mint from at all;
      # and Turkey assigns one "Sıra No" to two different organisations,
      # so the number alone does not identify a record either. +local_id+
      # is what resolves both — see that method for the fallback and
      # reservation policies.
      #
      # Harmonize reads each record back from its own YAML file, so this
      # layer has to agree with the fetcher's filenames — a fetch-only
      # fix keeps the second designee on disk and still loses it in the
      # graph.
      #
      # The SourceReference still carries the raw +reference_number+, so
      # every record keeps reporting the number Turkey actually published
      # — or none, where Turkey published none.
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Month names as Turkey writes them in a birth date, with the Turkish
        # letters folded to ASCII so "EKİM" and "Ekim" read the same
        TURKISH_MONTHS = {
          'ocak' => 1, 'subat' => 2, 'mart' => 3, 'nisan' => 4,
          'mayis' => 5, 'haziran' => 6, 'temmuz' => 7, 'agustos' => 8,
          'eylul' => 9, 'ekim' => 10, 'kasim' => 11, 'aralik' => 12
        }.freeze

        def initialize
          super(:tr)
        end

        # Transform TR entity to harmonized model
        # @param source [Object] source model
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source)
          entity = create_entity(source)
          entry = create_entry(source, entity)

          { entity: entity, entry: entry }
        end

        private

        # Create harmonized entity
        # @param source [Object] source model
        # @return [PersonEntity, OrganizationEntity]
        def create_entity(source)
          entity_type = map_entity_type(source)

          case entity_type
          when 'person'
            create_person_entity(source)
          else
            create_organization_entity(source)
          end
        end

        # Create person entity
        # @param source [Object] source model
        # @return [PersonEntity]
        def create_person_entity(source)
          Ammitto::PersonEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.local_id)
            entity.entity_type = 'person'
            entity.names = build_names(source)
            entity.birth_info = build_birth_info(source)
            entity.nationalities = [presence(source.nationality)].compact
            entity.addresses = build_addresses(source)
            entity.position = presence(source.title)
            entity.remarks = presence(source.remarks)
            entity.source_references = build_source_references(source)
          end
        end

        # Create organization entity
        # @param source [Object] source model
        # @return [OrganizationEntity]
        def create_organization_entity(source)
          Ammitto::OrganizationEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.local_id)
            entity.entity_type = 'organization'
            entity.names = build_names(source)
            entity.addresses = build_addresses(source)
            entity.remarks = presence(source.remarks)
            entity.source_references = build_source_references(source)
          end
        end

        # Build names array
        # @param source [Object] source model
        # @return [Array<NameVariant>]
        def build_names(source)
          names = []

          names << create_name_variant(full_name: source.name, is_primary: true) if source.name
          alias_names(source.aliases, person: map_entity_type(source) == 'person').each do |alias_name|
            next if alias_name.casecmp?(source.name.to_s)

            names << create_name_variant(full_name: alias_name)
          end

          names
        end

        # Turkey lists aliases in one cell as "a) X" and "b) Y", sometimes
        # on one line, and wraps long names onto the next line. Pieces are
        # cut at letter markers so wrapped names stay whole. Personal
        # alternatives also use commas; organization names keep their commas.
        # @param text [String, nil] the aliases cell
        # @param person [Boolean] whether commas delimit personal alternatives
        # @return [Array<String>]
        def alias_names(text, person:)
          plain = text.to_s.gsub(/<[^>]*>/, ' ')
          separator = person ? /(?:\A|\s)[a-z]\)\s+|,/i : /(?:\A|\s)[a-z]\)\s+/i
          plain.split(separator)
               .map { |piece| piece.gsub(/\s+/, ' ').strip.sub(/\s*;\z/, '') }
               .reject(&:empty?)
               .uniq(&:downcase)
        end

        # Turkey writes birth dates as ISO dates, bare years, year spans,
        # "D Month YYYY" in Turkish, or several of those marked "a)" and
        # "b)". Only a value that reads unambiguously becomes a date; a
        # value with a typo ("6 Mayısl969") is reported and left out,
        # because the general date reader would turn it into year 969.
        # @param source [Object] source model
        # @return [Array<BirthInfo>]
        def build_birth_info(source)
          place = presence(source.place_of_birth)
          city, country = place_parts(place)
          births = birth_date_values(source.date_of_birth).map do |value|
            create_birth_info(city: city, country: country, **value)
          end
          return births unless births.empty? && place

          [create_birth_info(city: city, country: country)]
        end

        # @param text [String, nil] the date of birth cell
        # @return [Array<Hash>] create_birth_info keywords, one per date
        def birth_date_values(text)
          return [] if presence(text).nil?

          text.to_s.split(/(?:\A|\s)[a-z]\)\s*/i).map(&:strip).reject(&:empty?)
              .filter_map { |part| birth_date_value(part) }
        end

        # @param part [String] one date as written
        # @return [Hash, nil] nil, after a report, when it reads no date
        def birth_date_value(part)
          case part
          when /\A(\d{4})-(\d{2})-(\d{2})\z/
            year, month, day = Regexp.last_match.captures
            day_month_year(day, month.to_i, year) || unreadable_birth_date(part)
          when /\A\d{4}\z/ then { year: part.to_i }
          when /\A(\d{4})\s*-\s*(\d{4})\z/
            from, to = Regexp.last_match.captures.map(&:to_i)
            # a backwards span is a typo; create_birth_info would raise and
            # fail the whole harmonize run
            from <= to ? { year_range_from: from, year_range_to: to } : unreadable_birth_date(part)
          when /\A(\d{1,2})\s+(\p{L}+)\s+(\d{4})\z/
            day, month, year = Regexp.last_match.captures
            day_month_year(day, TURKISH_MONTHS[month.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.tr('ı', 'i')], year) ||
              unreadable_birth_date(part)
          when /\A(\d{1,2})\.(\d{1,2})\.(\d{4})\z/
            day, month, year = Regexp.last_match.captures
            day_month_year(day, month.to_i, year) || unreadable_birth_date(part)
          else unreadable_birth_date(part)
          end
        end

        # @return [Hash, nil] nil when the numbers name no calendar day
        def day_month_year(day, month, year)
          return nil unless month && Date.valid_date?(year.to_i, month, day.to_i)

          { date: Date.new(year.to_i, month, day.to_i).iso8601 }
        end

        # @param part [String]
        # @return [nil]
        def unreadable_birth_date(part)
          Ammitto::ParseFailureVisibility.report(
            source: :tr, field: :date_of_birth, value: part,
            error: ArgumentError.new('not a date Turkey writes unambiguously')
          )
          nil
        end

        # "Ardebil, İran" is a city and a country; one word is a city.
        # @param place [String, nil]
        # @return [Array<String, nil>] city, country
        def place_parts(place)
          return [nil, nil] if place.nil?

          city, country = place.split(',', 2).map(&:strip)
          [city, Ammitto::Utils::Presence.presence(country)]
        end

        # @param source [Object] source model
        # @return [Array<Address>]
        def build_addresses(source)
          street = presence(source.address&.gsub(/<[^>]*>/, ' ')&.gsub(/[ \t]+/, ' '))
          # Some rows carry a passport number and its expiry in this column
          return [] if street.nil? || street.match?(/\A\d+ \(.*tarih/i)

          [create_address(street: street)]
        end

        # @param value [String, nil]
        # @return [String, nil] nil for a blank value
        def presence(value)
          Ammitto::Utils::Presence.presence(value&.strip)
        end

        # Build source references
        # @param source [Object] source model
        # @return [Array<SourceReference>]
        def build_source_references(source)
          [Ammitto::SourceReference.new(
            source_code: 'tr',
            reference_number: source.reference_number,
            retrieved_at: Time.now.utc.iso8601
          )]
        end

        # Map entity type
        # @param source [Object] source model
        # @return [String]
        def map_entity_type(source)
          source.entity_type&.downcase == 'person' ? 'person' : 'organization'
        end

        # Create sanction entry
        # @param source [Object] source model
        # @param entity [Entity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(source, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(source.local_id)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime(source.program)
            entry.status = 'active'
            entry.effects = build_effects(source)
            entry.period = create_period(source)
          end
        end

        # Create regime
        # @param program [String] program name
        # @return [SanctionRegime]
        def create_regime(program)
          code = case program
                 when /7262.*3\.A/i then 'TR-D'
                 when /7262/i then 'TR-D'
                 when /6415.*6/i then 'TR-B'
                 when /6415/i then 'TR-C'
                 else 'TR'
                 end

          Ammitto::SanctionRegime.new(
            name: "Turkey #{program || 'Sanctions'}",
            code: code
          )
        end

        # Build effects
        # @param source [Object] source model
        # @return [Array<SanctionEffect>]
        def build_effects(_source)
          # Turkey typically imposes asset freeze and entry ban
          [
            create_effect(effect_type: 'asset_freeze'),
            create_effect(effect_type: 'entry_ban')
          ]
        end

        # Create period
        # @param source [Object] source model
        # @return [TemporalPeriod]
        def create_period(source)
          Ammitto::TemporalPeriod.new(
            listed_date: parse_listed_date(source.listed_date),
            is_indefinite: true
          )
        end

        # A listing date Turkey writes that Date.parse cannot read
        # publishes as nil, so it is reported to keep a trace of what was
        # actually stated. Distinct from the
        # record-level identity refusals in SanctionsList/IntegrityError:
        # those stop a row from minting an IRI at all, this only loses
        # one field on a row that is otherwise published.
        # @param value [String, nil]
        # @return [Date, nil]
        def parse_listed_date(value)
          return nil if value.nil? || value.to_s.strip.empty?

          # The first date in this authority column is the listing date;
          # dates in its review/amendment note do not replace that date.
          text = value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
                      .downcase.tr('ı', 'i').gsub(/\s+/, ' ').strip
          match = text.match(/\A(\d{1,2}) ([a-z]+) (\d{4})(?:\s*\(([^()]*)\))?\z/)
          if match && (month = TURKISH_MONTHS[match[2]]) && listing_annotation?(match[4])
            return Date.new(match[3].to_i, month, match[1].to_i)
          end

          Date.parse(value.to_s)
        rescue ArgumentError => e
          Ammitto::ParseFailureVisibility.report(
            source: :tr, field: :listed_date, value: value, error: e
          )
          nil
        end

        def listing_annotation?(text)
          return true if text.nil?

          date = '\d{1,2} [a-z]+ \d{4}'
          text.match?(/\Adegisiklik #{date}\z/) ||
            text.match?(/\A#{date}(?: ve #{date})? tarih(?:ler)?inde gozden gecirilmistir\.\z/)
        end
      end
    end
  end
end
