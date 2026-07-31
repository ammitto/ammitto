# frozen_string_literal: true

module Ammitto
  module Ontology
    # Enumeration types for the sanctions ontology
    #
    # All enumerations are defined as frozen constants to ensure
    # immutability and single source of truth (MECE principle).
    #
    module Types
      # Entity types in the sanctions domain
      # @return [Array<Symbol>]
      ENTITY_TYPES = %i[person organization vessel aircraft].freeze

      # Identification document types
      # @return [Array<Symbol>]
      IDENTIFICATION_TYPES = %i[
        passport
        national_id
        tax_id
        drivers_license
        diplomatic_passport
        birth_certificate
        social_security
        company_registration
        vessel_registration
        aircraft_registration
        other
      ].freeze

      # Types of sanction effects/restrictions
      # @return [Array<Symbol>]
      SANCTION_EFFECT_TYPES = %i[
        asset_freeze
        travel_ban
        arms_embargo
        trade_restriction
        financial_prohibition
        service_prohibition
        investment_ban
        technology_transfer_ban
        visa_suspension
        aircraft_ban
        debarment
        entry_ban
        export_restriction
        sectoral_sanction
        transport_sanction
        vessel_ban
        import_ban
        export_ban
        financial_restriction
        service_restriction
        technology_restriction
        transaction_ban
        allow_statement
        cancel_stay_residence
        cancel_work_permit
        cooperate_investigation
        export_license_requirement
        fine
        import_license_requirement
        investigation
        maritime_restriction
        prohibit_cooperation
        prohibit_data_transmission
        prohibit_export_dual_use_items
        prohibit_export_gene_sequencers
        prohibit_export_specific_product
        prohibit_import_export
        prohibit_investment_new
        prohibit_sensitive_information_provision
        prohibit_transactions
        prohibit_transfer_provide_dual_use_items
        provide_information
        report_violation
        unreliable_entity_list
        visa_ban
        other
      ].freeze

      # Sanction entry status
      # @return [Array<Symbol>]
      SANCTION_STATUSES = %i[
        active
        delisted
        expired
        suspended
        pending
      ].freeze

      # Types of legal instruments
      # @return [Array<Symbol>]
      LEGAL_INSTRUMENT_TYPES = %i[
        regulation
        decision
        resolution
        law
        decree
        order
        directive
        proclamation
        executive_order
        other
      ].freeze

      # Name script/character set types (ISO 15924)
      # @return [Array<Symbol>]
      # Latn: Latin, Cyrl: Cyrillic, Arab: Arabic, Hani: Han,
      # Hebr: Hebrew, Beng: Bengali, Deva: Devanagari, Grek: Greek,
      # Jpan: Japanese (Han + Kana), Kana: Katakana, Hang: Hangul,
      # Kore: Korean (Hangul + Han), Thai: Thai. Comments must stay
      # outside the %i[] literal: Ruby would keep each comment word as
      # an enum member.
      NAME_SCRIPTS = %i[
        Latn
        Cyrl
        Arab
        Hani
        Hebr
        Beng
        Deva
        Grek
        Jpan
        Kana
        Hang
        Kore
        Thai
        other
      ].freeze

      # Scope of sanction effects
      # @return [Array<Symbol>]
      EFFECT_SCOPES = %i[
        full
        partial
        targeted
        sectoral
      ].freeze

      # Gender types
      # @return [Array<Symbol>]
      GENDERS = %i[m f male female other unknown].freeze

      # Valid entity type check
      # @param type [Symbol, String]
      # @return [Boolean]
      def self.valid_entity_type?(type)
        ENTITY_TYPES.include?(type.to_sym.downcase)
      end

      # Valid identification type check
      # @param type [Symbol, String]
      # @return [Boolean]
      def self.valid_identification_type?(type)
        IDENTIFICATION_TYPES.include?(type.to_sym.downcase)
      end

      # Valid sanction effect type check
      # @param type [Symbol, String]
      # @return [Boolean]
      def self.valid_effect_type?(type)
        SANCTION_EFFECT_TYPES.include?(type.to_sym.downcase)
      end

      # Valid sanction status check
      # @param status [Symbol, String]
      # @return [Boolean]
      def self.valid_status?(status)
        SANCTION_STATUSES.include?(status.to_sym.downcase)
      end

      # Valid legal instrument type check
      # @param type [Symbol, String]
      # @return [Boolean]
      def self.valid_instrument_type?(type)
        LEGAL_INSTRUMENT_TYPES.include?(type.to_sym.downcase)
      end

      # Valid script check
      # @param script [Symbol, String]
      # @return [Boolean]
      def self.valid_script?(script)
        NAME_SCRIPTS.include?(script.to_sym)
      end

      # Normalize entity type string
      # @param type [String, Symbol, nil]
      # @return [Symbol, nil]
      def self.normalize_entity_type(type)
        return nil if type.nil?

        normalized = type.to_sym.downcase
        ENTITY_TYPES.include?(normalized) ? normalized : nil
      end

      # Normalize identification type string
      # @param type [String, Symbol, nil]
      # @return [Symbol]
      def self.normalize_identification_type(type)
        return :other if type.nil?

        normalized = type.to_s.downcase
                         .gsub(/[-_\s]+/, '_')
                         .gsub(/passports?/, 'passport')
                         .gsub(/national_?ids?/, 'national_id')
                         .gsub(/tax_?ids?/, 'tax_id')
                         .gsub(/drivers?_?licenses?/, 'drivers_license')
                         .to_sym

        IDENTIFICATION_TYPES.include?(normalized) ? normalized : :other
      end

      # Normalize sanction effect type string
      # @param type [String, Symbol, nil]
      # @return [Symbol]
      def self.normalize_effect_type(type)
        return :other if type.nil?

        normalized = type.to_s.downcase.gsub(/[-\s]+/, '_').to_sym
        SANCTION_EFFECT_TYPES.include?(normalized) ? normalized : :other
      end

      # Normalize legal instrument type string
      # @param type [String, Symbol, nil]
      # @return [Symbol]
      def self.normalize_instrument_type(type)
        return :other if type.nil?

        normalized = type.to_s.downcase.gsub(/[-\s]+/, '_').to_sym
        LEGAL_INSTRUMENT_TYPES.include?(normalized) ? normalized : :other
      end

      # Normalize script detection from text
      # @param text [String, nil]
      # @return [Symbol]
      def self.detect_script(text)
        return :Latn if text.nil? || text.empty?

        return :Cyrl if text.match?(/\p{Cyrillic}/)
        return :Arab if text.match?(/\p{Arabic}/)
        return :Hebr if text.match?(/\p{Hebrew}/)
        return :Hani if text.match?(/\p{Han}/)
        return :Deva if text.match?(/\p{Devanagari}/)
        return :Beng if text.match?(/\p{Bengali}/)
        return :Grek if text.match?(/\p{Greek}/)
        return :Kana if text.match?(/\p{Hiragana}|\p{Katakana}/)
        return :Hang if text.match?(/\p{Hangul}/)
        return :Thai if text.match?(/\p{Thai}/)

        :Latn
      end

      # Normalize gender string
      # @param gender [String, Symbol, nil]
      # @return [Symbol, nil]
      def self.normalize_gender(gender)
        return nil if gender.nil?

        normalized = gender.to_s.upcase
        case normalized
        when 'M', 'MALE'
          :male
        when 'F', 'FEMALE'
          :female
        when 'U', 'UNKNOWN'
          :unknown
        else
          :other
        end
      end
    end
  end
end
