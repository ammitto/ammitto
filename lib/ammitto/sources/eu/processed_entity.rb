# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Simple address for processed data
      class ProcessedAddress < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :state, :string
        attribute :country, :string
        attribute :zip, :string

        yaml do
          map 'street', to: :street
          map 'city', to: :city
          map 'state', to: :state
          map 'country', to: :country
          map 'zip', to: :zip
        end

        def country_description
          country
        end

        def country_iso2_code
          nil
        end

        def region
          state
        end

        def zip_code
          zip
        end
      end

      # Simple name alias for transformer compatibility
      class SimpleNameAlias < Lutaml::Model::Serializable
        attribute :whole_name, :string
        attribute :first_name, :string
        attribute :middle_name, :string
        attribute :last_name, :string
        attribute :gender, :string

        yaml do
          map 'whole_name', to: :whole_name
        end
      end

      # Simple birthdate for transformer compatibility
      class SimpleBirthdate < Lutaml::Model::Serializable
        attribute :birthdate, :string
        attribute :circa, :boolean
        attribute :city, :string
        attribute :place, :string
        attribute :region, :string
        attribute :country_description, :string
        attribute :country_iso2_code, :string

        yaml do
          map 'birthdate', to: :birthdate
        end
      end

      # Simple subject type for transformer compatibility
      class SimpleSubjectType < Lutaml::Model::Serializable
        attribute :code, :string

        yaml do
          map 'code', to: :code
        end
      end

      # Processed entity from EU processed YAML files
      #
      # This model matches the simplified YAML format produced by the
      # data processing pipeline, not the original XML format.
      #
      # Example YAML:
      # ---
      # names:
      # - JSC "123 AVIATION REPAIR PLANT"
      # source: eu-data
      # entity_type: organization
      # country: ''
      # birthdate: ''
      # ref_number: EU.10982.59
      # ref_type: EU Reference Number
      # remark:
      # address:
      # - street: district Gorodok
      #   city: Staraya Russa
      #   country: RUSSIAN FEDERATION
      #
      class ProcessedEntity < Lutaml::Model::Serializable
        attribute :names, :string, collection: true
        attribute :source, :string
        attribute :entity_type, :string
        attribute :country, :string
        attribute :birthdate, :string
        attribute :ref_number, :string
        attribute :ref_type, :string
        attribute :remark, :string
        attribute :contact, :string
        attribute :addresses, ProcessedAddress, collection: true

        yaml do
          map 'names', to: :names
          map 'source', to: :source
          map 'entity_type', to: :entity_type
          map 'country', to: :country
          map 'birthdate', to: :birthdate
          map 'ref_number', to: :ref_number
          map 'ref_type', to: :ref_type
          map 'remark', to: :remark
          map 'contact', to: :contact
          map 'address', to: :addresses
        end

        # Helper methods for transformer compatibility
        def eu_reference_number
          ref_number
        end

        def person?
          entity_type.to_s.downcase == 'person'
        end

        def organization?
          !person?
        end

        def primary_name
          names&.first
        end

        def name_aliases
          names&.map { |n| SimpleNameAlias.new(whole_name: n) } || []
        end

        def regulations
          []
        end

        def primary_regulation
          nil
        end

        def programme
          nil
        end

        def gender
          nil
        end

        def nationalities
          []
        end

        def birthdates
          return [] if birthdate.nil? || birthdate.empty?

          [SimpleBirthdate.new(birthdate: birthdate)]
        end

        def identifications
          []
        end

        def subject_type
          SimpleSubjectType.new(code: entity_type)
        end

        def logical_id
          nil
        end

        def united_nation_id
          nil
        end

        def designation_details
          nil
        end
      end
    end
  end
end
