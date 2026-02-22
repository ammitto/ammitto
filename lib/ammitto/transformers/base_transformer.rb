# frozen_string_literal: true

module Ammitto
  module Transformers
    # BaseTransformer provides common functionality for transforming
    # source-specific models to the harmonized Ammitto ontology.
    #
    # Each source (UK, EU, UN, US, WB) should have its own transformer
    # that inherits from this base class.
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
      attr_reader :source_code

      # Initialize with source code
      # @param source_code [Symbol] the source identifier (e.g., :uk, :eu)
      def initialize(source_code)
        @source_code = source_code.to_sym
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

      # Generate a unique entity ID
      # @param reference_number [String] the source reference number
      # @return [String] the full URI
      def generate_entity_id(reference_number)
        "https://www.ammitto.org/entity/#{source_code}/#{sanitize_id(reference_number)}"
      end

      # Generate a unique sanction entry ID
      # @param reference_number [String] the source reference number
      # @return [String] the full URI
      def generate_entry_id(reference_number)
        "https://www.ammitto.org/entry/#{source_code}/#{sanitize_id(reference_number)}"
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
        id.to_s.gsub(%r{[/\\]}, '-')
      end

      # Parse a date string safely
      # @param date_str [String, nil] the date string
      # @return [Date, nil] parsed date or nil
      def parse_date(date_str)
        return nil if date_str.nil? || date_str.empty?

        begin
          Date.parse(date_str)
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

      # Create a BirthInfo from birth data
      # @param date [String, Date, nil] birth date
      # @param circa [Boolean] whether the date is approximate
      # @param city [String, nil] birth city
      # @param region [String, nil] birth region/state
      # @param country [String, nil] birth country
      # @param country_iso_code [String, nil] ISO country code
      # @return [BirthInfo] the birth info
      def create_birth_info(date: nil, circa: false, city: nil, region: nil, country: nil,
                            country_iso_code: nil)
        parsed_date = date.is_a?(Date) ? date : parse_date(date)

        Ammitto::BirthInfo.new(
          date: parsed_date,
          circa: circa,
          city: city,
          region: region,
          country: country,
          country_iso_code: country_iso_code
        )
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
