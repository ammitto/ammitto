# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Wb
      # Transformer converts World Bank source models to the harmonized
      # Ammitto ontology models.
      #
      # World Bank sanctions are "debarments" (procurement bans) rather than
      # traditional sanctions. They include cross-debarment agreements with
      # other development banks.
      #
      # @example Transforming a WB sanctioned firm
      #   transformer = Ammitto::Sources::Wb::Transformer.new
      #   result = transformer.transform(sanctioned_firm)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of debarment types to descriptions
        DEBARMENT_TYPES = {
          'D' => 'Debarred',
          'C' => 'Conditional Non-Debarment',
          'R' => 'Reinstated'
        }.freeze

        def initialize
          super(:wb)
        end

        # Transform a WB SanctionedFirm to ontology models
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm] the sanctioned firm
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(firm)
          @current_firm = firm

          entity = create_entity(firm)
          entry = create_entry(firm)

          # Link entity to entry
          entity.add_sanction_entry(entry)

          {
            entity: entity,
            entry: entry
          }
        ensure
          @current_firm = nil
        end

        private

        # Create the appropriate entity type based on firm type
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [PersonEntity, OrganizationEntity]
        def create_entity(firm)
          if firm.person?
            create_person_entity(firm)
          else
            create_organization_entity(firm)
          end
        end

        # Create a PersonEntity from a WB sanctioned firm
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [PersonEntity]
        def create_person_entity(firm)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(firm.supp_id.to_s),
            entity_type: 'person',
            names: [create_name_variant(full_name: firm.supp_name, is_primary: true)],
            addresses: create_address_from_firm(firm) ? [create_address_from_firm(firm)] : [],
            remarks: firm.add_supp_info
          )
        end

        # Create an OrganizationEntity from a WB sanctioned firm
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [OrganizationEntity]
        def create_organization_entity(firm)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(firm.supp_id.to_s),
            entity_type: 'organization',
            names: [create_name_variant(full_name: firm.supp_name, is_primary: true)],
            addresses: create_address_from_firm(firm) ? [create_address_from_firm(firm)] : [],
            remarks: firm.add_supp_info
          )
        end

        # Create a SanctionEntry from a WB sanctioned firm
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [SanctionEntry]
        def create_entry(firm)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(firm.supp_id.to_s),
            entity_id: generate_entity_id(firm.supp_id.to_s),
            authority: authority,
            regime: create_regime(code: 'DEBARMENT', name: 'World Bank Debarment'),
            effects: create_debarment_effects(firm),
            period: create_period(
              effective_date: parse_wb_date(firm.debar_from_date),
              expiry_date: parse_wb_date(firm.debar_to_date)
            ),
            status: determine_status(firm),
            reference_number: firm.supp_id.to_s,
            remarks: firm.debar_reason,
            raw_source_data: create_raw_source_data(
              source_format: 'json',
              source_specific_fields: {
                'wb:suppTypeCode' => firm.supp_type_code,
                'wb:debarType' => firm.debar_type,
                'wb:debarTypeDesc' => DEBARMENT_TYPES[firm.debar_type],
                'wb:suppPreAcrn' => firm.supp_pre_acrn,
                'wb:suppPostAcrn' => firm.supp_post_acrn,
                'wb:legacyFlag' => firm.legacy_flg,
                'wb:unSuppFlag' => firm.un_supp_flg,
                'wb:ineligFlag' => firm.inelig_flg,
                'wb:crossDebarment' => firm.crpd_match,
                'wb:crossDebarmentStatus' => firm.crpd_stat,
                'wb:eligStatus' => firm.elig_stat,
                'wb:suppEligStat' => firm.supp_elig_stat,
                'wb:ineligiblyStatus' => firm.ineligibly_status
              }
            )
          )
        end

        # Create address from WB firm data
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [Address, nil]
        def create_address_from_firm(firm)
          return nil unless has_address_data?(firm)

          create_address(
            street: firm.supp_addr,
            city: firm.supp_city,
            state: [firm.supp_state_code, firm.supp_prov_name].compact.first,
            country: firm.country_name,
            country_iso_code: firm.land1,
            postal_code: firm.supp_zip_code || firm.supp_post_code
          )
        end

        # Check if firm has address data
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [Boolean]
        def has_address_data?(firm)
          firm.supp_addr || firm.supp_city || firm.country_name || firm.land1
        end

        # Create debarment effects
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [Array<SanctionEffect>]
        def create_debarment_effects(firm)
          effects = []

          # Primary effect is always debarment
          effects << create_effect(
            effect_type: 'debarment',
            scope: 'full',
            description: 'Excluded from World Bank-financed contracts'
          )

          # If cross-debarred, add additional banks
          if firm.cross_debarred?
            effects << create_effect(
              effect_type: 'debarment',
              scope: 'full',
              description: 'Cross-debarred by other development banks (AfDB, ADB, EBRD, IADB)'
            )
          end

          effects
        end

        # Determine sanction status
        # @param firm [Ammitto::Sources::Wb::SanctionedFirm]
        # @return [String]
        def determine_status(firm)
          if firm.debar_to_date && parse_wb_date(firm.debar_to_date) && parse_wb_date(firm.debar_to_date) < Date.today
            return 'expired'
          end

          # Check eligibility status
          case firm.supp_elig_stat&.upcase
          when 'E'
            'active'
          when 'R'
            'resumed'
          when 'S'
            'suspended'
          when 'T'
            'terminated'
          when 'D'
            'delisted'
          else
            'active'
          end
        end

        # Parse WB date format
        # WB uses YYYY-MM-DD format
        # @param date_str [String, nil]
        # @return [Date, nil]
        def parse_wb_date(date_str)
          return nil if date_str.nil? || date_str.empty?

          parse_date(date_str)
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::WbTransformer = Ammitto::Sources::Wb::Transformer
