# frozen_string_literal: true

require_relative '../utils/iri_sanitizer'
require_relative '../utils/list_types_registry'

module Ammitto
  module Transformers
    # BaseTransformer provides common functionality for transforming
    # source-specific models to the harmonized Ammitto ontology.
    #
    # Each source (UK, EU, UN, US, WB) should have its own transformer
    # that inherits from this base class.
    #
    # == Normalized IRI Structure
    #
    # Entities are LIST-AGNOSTIC (can appear on multiple lists):
    #   https://www.ammitto.org/entity/{source}/{local_id}
    #
    # Entries are LIST-SPECIFIC (junction records linking entity to list):
    #   https://www.ammitto.org/entry/{source}/{list_type}/{local_id}
    #
    # @example Creating a transformer
    #   class UkTransformer < BaseTransformer
    #     def transform(designation)
    #       {
    #         entity: create_entity(designation),
    #         entry: create_entry(designation)
    #       }
    #     end
    #   end
    #
    class BaseTransformer
      attr_reader :source_code, :list_type

      # Initialize with source code and optional list type
      # @param source_code [Symbol] the source identifier (e.g., :uk, :eu)
      # @param list_type [String, nil] optional list type (e.g., "consolidated-list")
      def initialize(source_code, list_type: nil)
        @source_code = source_code.to_sym
        @list_type = list_type || default_list_type
      end

      # Transform source model to ontology models
      # @param source_model [Object] the source-specific model
      # @return [Hash] { entity: Entity, entry: SanctionEntry }
      def transform(source_model)
        raise NotImplementedError, 'Subclasses must implement #transform'
      end

      # Transform a collection of source models
      # @param source_models [Array<Object>] collection of source models
      # @return [Array<Hash>] array of transformation results
      def transform_all(source_models)
        source_models.map { |model| transform(model) }
      end

      protected

      # Generate a unique entity ID (LIST-AGNOSTIC).
      # Entities can appear on multiple lists, so no list_type in IRI.
      #
      # @param local_id [String] the local entity identifier
      # @return [String] the full entity URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      # @example
      #   generate_entity_id("mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
      #
      def generate_entity_id(local_id)
        Utils::IriSanitizer.entity_iri(source_code.to_s, local_id)
      end

      # Generate a unique entry ID (LIST-SPECIFIC).
      # Entries link entities to specific lists.
      #
      # @param local_id [String] the local entry identifier
      # @param entry_list_type [String, nil] optional list type override
      # @return [String] the full entry URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      # @example
      #   generate_entry_id("mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries"
      #
      def generate_entry_id(local_id, entry_list_type: nil)
        effective_list_type = entry_list_type || list_type || default_list_type
        Utils::IriSanitizer.entry_iri(source_code.to_s, effective_list_type, local_id)
      end

      # Generate a list type IRI.
      #
      # @param list_type_id [String, nil] optional list type override
      # @return [String] the full list URI
      #
      def generate_list_id(list_type_id: nil)
        effective_list_type = list_type_id || list_type || default_list_type
        Utils::IriSanitizer.list_type_iri(source_code.to_s, effective_list_type)
      end

      # Generate an announcement ID (LIST-AGNOSTIC).
      #
      # @param local_id [String] the local announcement identifier
      # @return [String] the full announcement URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def generate_announcement_id(local_id)
        Utils::IriSanitizer.announcement_iri(source_code.to_s, local_id)
      end

      # Generate a legal instrument ID (LIST-AGNOSTIC).
      #
      # @param local_id [String] the local legal instrument identifier
      # @return [String] the full legal instrument URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def generate_legal_instrument_id(local_id)
        Utils::IriSanitizer.legal_instrument_iri(source_code.to_s, local_id)
      end

      # Get the default list type for this source.
      #
      # @return [String, nil] the default list type or nil
      #
      def default_list_type
        Utils::ListTypesRegistry.default_list_type(source_code.to_s)
      end

      # Get all available list types for this source.
      #
      # @return [Array<String>] list of available list types
      #
      def available_list_types
        Utils::ListTypesRegistry.list_types_for(source_code.to_s)&.keys || []
      end

      # Get the authority for this source
      # @return [Authority] the authority object
      def authority
        @authority ||= Ammitto::Authority.find(source_code.to_s)
      end

      # Sanitize an ID for use in URIs
      # @param id [String] the raw ID
      # @return [String] sanitized ID
      def sanitize_id(id)
        Utils::IriSanitizer.sanitize(id)
      end

      # Parse a date string safely
      # @param date_str [String, Date, nil] the date string or Date object
      # @return [Date, nil] parsed date or nil
      def parse_date(date_str)
        return nil if date_str.nil?
        return date_str if date_str.is_a?(Date)
        return nil if date_str.to_s.empty?

        begin
          Date.parse(date_str.to_s)
        rescue Date::Error
          nil
        end
      end

      # Create a NameVariant from name parts
      # @param full_name [String, nil] full name
      # @param first_name [String, nil] first name
      # @param middle_name [String, nil] middle name
      # @param last_name [String, nil] last name
      # @param script [String, nil] script (Latn, Cyrl, etc.)
      # @param is_primary [Boolean] whether this is the primary name
      # @return [NameVariant] the name variant
      def create_name_variant(full_name: nil, first_name: nil, middle_name: nil,
                              last_name: nil, script: nil, is_primary: false)
        Ammitto::NameVariant.new(
          full_name: full_name,
          first_name: first_name,
          middle_name: middle_name,
          last_name: last_name,
          script: script,
          is_primary: is_primary
        )
      end

      # Create an Address from address parts
      # @param street [String, nil] street address
      # @param city [String, nil] city
      # @param state [String, nil] state/province
      # @param country [String, nil] country name
      # @param country_iso_code [String, nil] ISO country code
      # @param postal_code [String, nil] postal code
      # @return [Address] the address
      def create_address(street: nil, city: nil, state: nil, country: nil,
                         country_iso_code: nil, postal_code: nil)
        Ammitto::Address.new(
          street: street,
          city: city,
          state: state,
          country: country,
          country_iso_code: country_iso_code,
          postal_code: postal_code
        )
      end

      # Create a BirthInfo from birth data.
      #
      # Invariant: BirthInfo#date is set only when the source states a
      # complete day-month-year; a bare or partial year rides in
      # BirthInfo#year and is never padded into an invented date.
      # @param date [String, Date, nil] birth date
      # @param circa [Boolean] whether the date is approximate
      # @param city [String, nil] birth city
      # @param region [String, nil] birth region/state
      # @param country [String, nil] birth country
      # @param country_iso_code [String, nil] ISO country code
      # @param year [Integer, String, nil] source-stated birth year
      # @return [BirthInfo] the birth info
      def create_birth_info(date: nil, circa: false, city: nil, region: nil, country: nil,
                            country_iso_code: nil, year: nil)
        parsed_date = parse_complete_date(date)

        Ammitto::BirthInfo.new(
          date: parsed_date,
          circa: circa,
          city: city,
          region: region,
          country: country,
          country_iso_code: country_iso_code,
          year: normalize_year(year) || parsed_date&.year || extract_birth_year(date)
        )
      end

      # Parse a value into a Date only when it states day, month and year.
      # Partial expressions ("1975", "Oct 1988", "00/00/1963") yield nil
      # instead of a date padded with invented components. Date instances
      # pass through: the caller already resolved them.
      # @param value [Date, String, nil]
      # @return [Date, nil]
      def parse_complete_date(value)
        return value if value.is_a?(Date)

        str = value.to_s.strip
        return nil if str.empty?

        parts = Date._parse(str)
        return nil unless parts[:year] && parts[:mon] && parts[:mday]

        Date.new(parts[:year], parts[:mon], parts[:mday])
      rescue Date::Error
        nil
      end

      # Year stated by a partial date string ("1975", "circa 1975",
      # "Oct 1988", "00/00/1963"). A range such as "1962 to 1964" names
      # no single year and yields nil — range handling is a separate,
      # dedicated concern. That rejection is stated here rather than
      # left to Date._parse, which returns no year for today's range
      # spellings only incidentally.
      # @param value [Object] candidate date string
      # @return [Integer, nil]
      def extract_birth_year(value)
        return nil unless value.is_a?(String)

        str = value.strip.sub(/\A(?:circa|approximately|c\.?)\s*/i, '')
        return nil if multiple_years?(str)
        return str.to_i if /\A\d{4}\z/.match?(str)

        year = Date._parse(str)[:year]
        year&.positive? ? year : nil
      end

      # Whether a date string names more than one year — "1962 to 1964",
      # "between 1962 and 1964", "1962-1964". Such a string states a
      # range, not a birth year. Years are matched on word boundaries so
      # a run of digits ("19620101") is not read as two of them.
      # @param value [String] date string, circa marker already stripped
      # @return [Boolean]
      def multiple_years?(value)
        value.scan(/\b\d{4}\b/).uniq.size > 1
      end

      # Whether a source date string marks itself approximate
      # ("circa 1960", "c. 1955", "c 1955", "approximately 1965").
      # The bare "c" form is recognized because extract_birth_year
      # strips it and au's FlexibleDate parser reads it as circa; without
      # it "c 1955" yielded a year with circa left false.
      # @param value [Object] candidate date string
      # @return [Boolean]
      def circa_string?(value)
        value.is_a?(String) &&
          value.strip.match?(/\A(?:circa|approximately|c\.?)\s/i)
      end

      # Coerce a source-stated year to a positive Integer
      # @param value [Integer, String, nil]
      # @return [Integer, nil]
      def normalize_year(value)
        year = value.is_a?(Integer) ? value : value.to_s[/\A\d{4}\z/]&.to_i
        year&.positive? ? year : nil
      end

      # Create a SanctionRegime
      # @param name [String, nil] regime name
      # @param code [String, nil] regime code
      # @param description [String, nil] regime description
      # @return [SanctionRegime] the regime
      def create_regime(name: nil, code: nil, description: nil)
        Ammitto::SanctionRegime.new(
          name: name,
          code: code,
          description: description
        )
      end

      # Create a TemporalPeriod
      # @param listed_date [String, Date, nil] listing date
      # @param effective_date [String, Date, nil] effective date
      # @param expiry_date [String, Date, nil] expiry date
      # @param last_updated [String, nil] last update timestamp
      # @return [TemporalPeriod] the period
      def create_period(listed_date: nil, effective_date: nil, expiry_date: nil,
                        last_updated: nil)
        Ammitto::TemporalPeriod.new(
          listed_date: listed_date.is_a?(Date) ? listed_date : parse_date(listed_date),
          effective_date: effective_date.is_a?(Date) ? effective_date : parse_date(effective_date),
          expiry_date: expiry_date.is_a?(Date) ? expiry_date : parse_date(expiry_date),
          is_indefinite: expiry_date.nil?,
          last_updated: last_updated
        )
      end

      # Create a SanctionEffect
      # @param effect_type [String] the effect type
      # @param scope [String, nil] the scope (full, partial, limited)
      # @param description [String, nil] description
      # @return [SanctionEffect] the effect
      def create_effect(effect_type:, scope: 'full', description: nil)
        Ammitto::SanctionEffect.new(
          effect_type: effect_type,
          scope: scope,
          description: description
        )
      end

      # Create a SanctionReason
      # @param category [String] the reason category
      # @param description [String, nil] description text
      # @param language [String] language code (default: 'en')
      # @return [SanctionReason] the reason
      def create_reason(category:, description: nil, language: 'en')
        descriptions = []
        if description
          descriptions << Ammitto::Ontology::ValueObjects::LocalizedString.new(
            value: description,
            language: language,
            is_primary: true
          )
        end

        Ammitto::SanctionReason.new(
          category: category,
          description: descriptions
        )
      end

      # Create a RawSourceData
      # @param source_file [String, nil] source file name
      # @param source_format [String] format (xml, json, etc.)
      # @param raw_content [String, nil] raw content
      # @param source_specific_fields [Hash, nil] source-specific data
      # @return [RawSourceData] the raw source data
      def create_raw_source_data(source_file: nil, source_format: 'xml',
                                 raw_content: nil, source_specific_fields: nil)
        Ammitto::RawSourceData.new(
          source_file: source_file,
          source_format: source_format,
          raw_content: raw_content,
          source_specific_fields: source_specific_fields || {}
        )
      end

      # Create an Identification
      # @param type [String, nil] document type
      # @param number [String, nil] document number
      # @param issuing_country [String, nil] issuing country
      # @param note [String, nil] additional notes
      # @return [Identification] the identification
      def create_identification(type: nil, number: nil, issuing_country: nil,
                                note: nil)
        Ammitto::Identification.new(
          type: type,
          number: number,
          issuing_country: issuing_country,
          note: note
        )
      end
    end
  end
end
