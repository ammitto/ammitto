# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Nz
      # Entity represents a sanctioned organization/entity in the NZ register
      #
      class Entity < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :unique_identifier, :string
        attribute :name, :string # Stored in first_name column as "Name of Asset"
        attribute :name_of_service, :string
        attribute :alias_alternate_spellings, :string
        attribute :address, :string
        attribute :sanction_status, :string
        attribute :date_of_sanction, :date
        attribute :date_of_additional_sanction, :date
        attribute :travel_ban, :string
        attribute :asset_freeze, :string
        attribute :aircraft_ban, :string
        attribute :ship_ban, :string
        attribute :service_prohibition, :string
        attribute :dealing_with_securities, :string
        attribute :general_rationale_for_sanction, :string

        yaml do
          map 'type', to: :type
          map 'unique_identifier', to: :unique_identifier
          map 'name', to: :name
          map 'name_of_service', to: :name_of_service
          map 'alias_alternate_spellings', to: :alias_alternate_spellings
          map 'address', to: :address
          map 'sanction_status', to: :sanction_status
          map 'date_of_sanction', to: :date_of_sanction
          map 'date_of_additional_sanction', to: :date_of_additional_sanction
          map 'travel_ban', to: :travel_ban
          map 'asset_freeze', to: :asset_freeze
          map 'aircraft_ban', to: :aircraft_ban
          map 'ship_ban', to: :ship_ban
          map 'service_prohibition', to: :service_prohibition
          map 'dealing_with_securities', to: :dealing_with_securities
          map 'general_rationale_for_sanction', to: :general_rationale_for_sanction
        end

        # Create Entity from row data hash
        # @param data [Hash] row data
        # @return [Entity]
        def self.from_row_data(data)
          entity = new
          entity.type = 'Entity'
          entity.unique_identifier = data['unique_identifier']
          # Entity name is in the "first_name" column (labeled "Name of Asset" in header)
          entity.name = data['first_name'] || data['name_of_asset']
          entity.name_of_service = data['name_of_service']
          entity.alias_alternate_spellings = data['alias_alternate_spellings']
          entity.address = data['address']
          entity.sanction_status = data['sanction_status']
          entity.date_of_sanction = parse_date(data['date_of_sanction'])
          entity.date_of_additional_sanction = parse_date(data['date_of_additional_sanction'])
          entity.travel_ban = data['travel_ban']
          entity.asset_freeze = data['asset_freeze']
          entity.aircraft_ban = data['aircraft_ban']
          entity.ship_ban = data['ship_ban']
          entity.service_prohibition = data['service_prohibition']
          entity.dealing_with_securities = data['dealing_with_securities']
          entity.general_rationale_for_sanction = data['general_rationale_for_sanction']
          entity
        end

        # Parse date value
        def self.parse_date(value)
          return nil if value.nil?
          return value if value.is_a?(Date)

          begin
            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        end

        # Get reference number (alias for unique_identifier)
        def reference_number
          unique_identifier
        end

        # Convert to hash for YAML serialization
        def to_hash
          {
            'type' => type,
            'unique_identifier' => unique_identifier,
            'name' => name,
            'name_of_service' => name_of_service,
            'alias_alternate_spellings' => alias_alternate_spellings,
            'address' => address,
            'sanction_status' => sanction_status,
            'date_of_sanction' => date_of_sanction&.iso8601,
            'date_of_additional_sanction' => date_of_additional_sanction&.iso8601,
            'travel_ban' => travel_ban,
            'asset_freeze' => asset_freeze,
            'aircraft_ban' => aircraft_ban,
            'ship_ban' => ship_ban,
            'service_prohibition' => service_prohibition,
            'dealing_with_securities' => dealing_with_securities,
            'general_rationale_for_sanction' => general_rationale_for_sanction
          }.compact
        end
      end
    end
  end
end
