# frozen_string_literal: true

module Ammitto
  module Sources
    module Uk
      # Sanctions imposed indicators for UK designation
      #
      # UK schema has 15+ boolean indicators for different sanction types.
      # These map to our harmonized SanctionEffect types.
      #
      # @example
      #   indicators = Ammitto::Sources::Uk::SanctionsIndicators.from_xml(xml)
      #   if indicators.asset_freeze
      #     puts "Asset freeze applies"
      #   end
      #
      class SanctionsIndicators < Lutaml::Model::Serializable
        # Financial sanctions
        attribute :asset_freeze, :boolean
        attribute :trust_services_sanctions, :boolean
        attribute :financial_market_prohibitions, :boolean

        # Trade sanctions
        attribute :arms_embargo, :boolean
        attribute :targeted_arms_embargo, :boolean
        attribute :trade_sanctions, :boolean
        attribute :import_sanctions, :boolean
        attribute :export_sanctions, :boolean
        attribute :technical_assistance_related_to_aircraft, :boolean

        # Transport sanctions
        attribute :travel_ban, :boolean
        attribute :prevention_of_port_entry, :boolean
        attribute :chartering_of_ships, :boolean
        attribute :crew_servicing_of_ships_and_aircraft, :boolean
        attribute :prevention_of_chartering_of_ships_and_aircraft, :boolean

        # Business restrictions
        attribute :prevention_of_business_arrangements, :boolean
        attribute :closure_of_representative_offices, :boolean

        # Other
        attribute :director_disqualification_sanction, :boolean
        attribute :deflag, :boolean
        attribute :owned_or_controlled, :boolean
        attribute :designated_person, :boolean
        attribute :detained_or_in_transit, :boolean
        attribute :other_sanctions, :boolean

        xml do
          root 'SanctionsImposedIndicators'

          # Financial
          map_element 'AssetFreeze', to: :asset_freeze
          map_element 'TrustServicesSanctions', to: :trust_services_sanctions
          map_element 'FinancialMarketProhibitions', to: :financial_market_prohibitions

          # Trade
          map_element 'ArmsEmbargo', to: :arms_embargo
          map_element 'TargetedArmsEmbargo', to: :targeted_arms_embargo
          map_element 'TradeSanctions', to: :trade_sanctions
          map_element 'ImportSanctions', to: :import_sanctions
          map_element 'ExportSanctions', to: :export_sanctions
          map_element 'TechnicalAssistanceRelatedToAircraft',
                      to: :technical_assistance_related_to_aircraft

          # Transport
          map_element 'TravelBan', to: :travel_ban
          map_element 'PreventionOfPortEntry', to: :prevention_of_port_entry
          map_element 'CharteringOfShips', to: :chartering_of_ships
          map_element 'CrewServicingOfShipsAndAircraft',
                      to: :crew_servicing_of_ships_and_aircraft
          map_element 'PreventionOfCharteringOfShipsAndAircraft',
                      to: :prevention_of_chartering_of_ships_and_aircraft

          # Business
          map_element 'PreventionOfBusinessArrangements',
                      to: :prevention_of_business_arrangements
          map_element 'ClosureOfRepresentativeOffices',
                      to: :closure_of_representative_offices

          # Other
          map_element 'DirectorDisqualificationSanction',
                      to: :director_disqualification_sanction
          map_element 'Deflag', to: :deflag
          map_element 'OwnedOrControlled', to: :owned_or_controlled
          map_element 'DesignatedPerson', to: :designated_person
          map_element 'DetainedOrInTransit', to: :detained_or_in_transit
          map_element 'OtherSanctions', to: :other_sanctions
        end

        yaml do
          # Financial
          map 'asset_freeze', to: :asset_freeze
          map 'trust_services_sanctions', to: :trust_services_sanctions
          map 'financial_market_prohibitions', to: :financial_market_prohibitions

          # Trade
          map 'arms_embargo', to: :arms_embargo
          map 'targeted_arms_embargo', to: :targeted_arms_embargo
          map 'trade_sanctions', to: :trade_sanctions
          map 'import_sanctions', to: :import_sanctions
          map 'export_sanctions', to: :export_sanctions
          map 'technical_assistance_related_to_aircraft',
              to: :technical_assistance_related_to_aircraft

          # Transport
          map 'travel_ban', to: :travel_ban
          map 'prevention_of_port_entry', to: :prevention_of_port_entry
          map 'chartering_of_ships', to: :chartering_of_ships
          map 'crew_servicing_of_ships_and_aircraft',
              to: :crew_servicing_of_ships_and_aircraft
          map 'prevention_of_chartering_of_ships_and_aircraft',
              to: :prevention_of_chartering_of_ships_and_aircraft

          # Business
          map 'prevention_of_business_arrangements',
              to: :prevention_of_business_arrangements
          map 'closure_of_representative_offices',
              to: :closure_of_representative_offices

          # Other
          map 'director_disqualification_sanction',
              to: :director_disqualification_sanction
          map 'deflag', to: :deflag
          map 'owned_or_controlled', to: :owned_or_controlled
          map 'designated_person', to: :designated_person
          map 'detained_or_in_transit', to: :detained_or_in_transit
          map 'other_sanctions', to: :other_sanctions
        end

        # Map UK indicators to harmonized effect types
        # @return [Array<Hash>] array of effect type hashes
        def to_effect_types
          effects = []

          effects << { type: 'asset_freeze', scope: 'full' } if asset_freeze
          effects << { type: 'travel_ban', scope: 'full' } if travel_ban
          effects << { type: 'arms_embargo', scope: 'full' } if arms_embargo
          effects << { type: 'arms_embargo', scope: 'targeted' } if targeted_arms_embargo
          effects << { type: 'trade_restriction', scope: 'full' } if trade_sanctions
          effects << { type: 'import_ban', scope: 'full' } if import_sanctions
          effects << { type: 'export_ban', scope: 'full' } if export_sanctions
          effects << { type: 'financial_restriction', scope: 'full' } if trust_services_sanctions
          effects << { type: 'financial_restriction', scope: 'full' } if financial_market_prohibitions
          effects << { type: 'debarment', scope: 'full' } if director_disqualification_sanction
          effects << { type: 'service_restriction', scope: 'full' } if prevention_of_business_arrangements
          effects << { type: 'entry_ban', scope: 'full' } if prevention_of_port_entry
          effects << { type: 'technology_restriction', scope: 'full' } if technical_assistance_related_to_aircraft

          effects
        end

        # Get list of active indicators
        # @return [Array<Symbol>]
        def active_indicators
          %i[
            asset_freeze trust_services_sanctions financial_market_prohibitions
            arms_embargo targeted_arms_embargo trade_sanctions
            import_sanctions export_sanctions
            technical_assistance_related_to_aircraft
            travel_ban prevention_of_port_entry
            chartering_of_ships crew_servicing_of_ships_and_aircraft
            prevention_of_chartering_of_ships_and_aircraft
            prevention_of_business_arrangements
            closure_of_representative_offices
            director_disqualification_sanction
            deflag owned_or_controlled designated_person
            detained_or_in_transit other_sanctions
          ].select { |attr| send(attr) == true }
        end
      end
    end
  end
end
