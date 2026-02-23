# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Nz
      # Ship represents a sanctioned vessel in the NZ register
      #
      class Ship < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :unique_identifier, :string
        attribute :imo_number, :string
        attribute :name, :string
        attribute :date_of_sanction, :date
        attribute :alias_alternate_names, :string
        attribute :date_of_additional_sanction, :date
        attribute :sanction_status, :string
        attribute :travel_ban, :string
        attribute :asset_freeze, :string
        attribute :aircraft_ban, :string
        attribute :ship_ban, :string
        attribute :service_prohibition, :string
        attribute :dealing_with_securities, :string
        attribute :date_record_deleted, :date
        attribute :record_deleted_flag, :string
        attribute :reason_for_deletion, :string

        # Create Ship from row data hash
        # @param data [Hash] row data
        # @return [Ship]
        def self.from_row_data(data)
          ship = new
          ship.type = data['type']
          ship.unique_identifier = data['unique_identifier']
          ship.imo_number = data['imo_number']&.to_s
          ship.name = data['name_of_ship_as_of_date_of_sanction']
          ship.date_of_sanction = parse_date(data['date_of_sanction'])
          ship.alias_alternate_names = data['alias_alternate_names']
          ship.date_of_additional_sanction = parse_date(data['date_of_additional_sanction'])
          ship.sanction_status = data['sanction_status']
          ship.travel_ban = data['travel_ban']
          ship.asset_freeze = data['asset_freeze']
          ship.aircraft_ban = data['aircraft_ban']
          ship.ship_ban = data['ship_ban']
          ship.service_prohibition = data['service_prohibition']
          ship.dealing_with_securities = data['dealing_with_securities']
          ship.date_record_deleted = parse_date(data['date_record_deleted'])
          ship.record_deleted_flag = data['record_deleted_flag']
          ship.reason_for_deletion = data['reason_for_deletion']
          ship
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
            'imo_number' => imo_number,
            'name' => name,
            'date_of_sanction' => date_of_sanction&.iso8601,
            'alias_alternate_names' => alias_alternate_names,
            'date_of_additional_sanction' => date_of_additional_sanction&.iso8601,
            'sanction_status' => sanction_status,
            'travel_ban' => travel_ban,
            'asset_freeze' => asset_freeze,
            'aircraft_ban' => aircraft_ban,
            'ship_ban' => ship_ban,
            'service_prohibition' => service_prohibition,
            'dealing_with_securities' => dealing_with_securities,
            'date_record_deleted' => date_record_deleted&.iso8601,
            'record_deleted_flag' => record_deleted_flag,
            'reason_for_deletion' => reason_for_deletion
          }.compact
        end
      end
    end
  end
end
