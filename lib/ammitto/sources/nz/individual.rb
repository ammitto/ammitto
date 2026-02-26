# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Nz
      # Individual represents a sanctioned individual in the NZ register
      #
      class Individual < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :unique_identifier, :string
        attribute :first_name, :string
        attribute :middle_names, :string
        attribute :last_name, :string
        attribute :dob, :date
        attribute :title, :string
        attribute :alias_alternate_spellings, :string
        attribute :address, :string
        attribute :place_of_birth, :string
        attribute :citizenship, :string
        attribute :citizenship_2, :string
        attribute :citizenship_3, :string
        attribute :passport_number, :string
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
        attribute :associates_relatives, :string

        yaml do
          map 'type', to: :type
          map 'unique_identifier', to: :unique_identifier
          map 'first_name', to: :first_name
          map 'middle_names', to: :middle_names
          map 'last_name', to: :last_name
          map 'dob', to: :dob
          map 'title', to: :title
          map 'alias_alternate_spellings', to: :alias_alternate_spellings
          map 'address', to: :address
          map 'place_of_birth', to: :place_of_birth
          map 'citizenship', to: :citizenship
          map 'citizenship_2', to: :citizenship_2
          map 'citizenship_3', to: :citizenship_3
          map 'passport_number', to: :passport_number
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
          map 'associates_relatives', to: :associates_relatives
        end

        # Create Individual from row data hash
        # @param data [Hash] row data
        # @return [Individual]
        def self.from_row_data(data)
          individual = new
          individual.type = 'Individual'
          individual.unique_identifier = data['unique_identifier']
          individual.first_name = data['first_name']
          individual.middle_names = data['middle_name_s']
          individual.last_name = data['last_name']
          individual.dob = parse_date(data['dob'])
          individual.title = data['title']
          individual.alias_alternate_spellings = data['alias_alternate_spellings']
          individual.address = data['address']
          individual.place_of_birth = data['place_of_birth']
          individual.citizenship = data['citizenship']
          individual.citizenship_2 = data['citizenship_2']
          individual.citizenship_3 = data['citizenship_3']
          individual.passport_number = data['passport_number']
          individual.sanction_status = data['sanction_status']
          individual.date_of_sanction = parse_date(data['date_of_sanction'])
          individual.date_of_additional_sanction = parse_date(data['date_of_additional_sanction'])
          individual.travel_ban = data['travel_ban']
          individual.asset_freeze = data['asset_freeze']
          individual.aircraft_ban = data['aircraft_ban']
          individual.ship_ban = data['ship_ban']
          individual.service_prohibition = data['service_prohibition']
          individual.dealing_with_securities = data['dealing_with_securities']
          individual.general_rationale_for_sanction = data['general_rationale_for_sanction']
          individual.associates_relatives = data['associates_relatives']
          individual
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

        # Get full name
        def full_name
          parts = [first_name, middle_names, last_name].compact.reject(&:empty?)
          parts.join(' ')
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
            'first_name' => first_name,
            'middle_names' => middle_names,
            'last_name' => last_name,
            'full_name' => full_name,
            'dob' => dob&.iso8601,
            'title' => title,
            'alias_alternate_spellings' => alias_alternate_spellings,
            'address' => address,
            'place_of_birth' => place_of_birth,
            'citizenship' => citizenship,
            'citizenship_2' => citizenship_2,
            'citizenship_3' => citizenship_3,
            'passport_number' => passport_number,
            'sanction_status' => sanction_status,
            'date_of_sanction' => date_of_sanction&.iso8601,
            'date_of_additional_sanction' => date_of_additional_sanction&.iso8601,
            'travel_ban' => travel_ban,
            'asset_freeze' => asset_freeze,
            'aircraft_ban' => aircraft_ban,
            'ship_ban' => ship_ban,
            'service_prohibition' => service_prohibition,
            'dealing_with_securities' => dealing_with_securities,
            'general_rationale_for_sanction' => general_rationale_for_sanction,
            'associates_relatives' => associates_relatives
          }.compact
        end
      end
    end
  end
end
