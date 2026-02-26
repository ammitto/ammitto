# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Sanction entity from EU sanctions list
      #
      # Example XML:
      # <sanctionEntity designationDetails="" unitedNationId="" euReferenceNumber="EU.27.28" logicalId="13">
      #   <remark>UNSC RESOLUTION 1483</remark>
      #   <regulation ...>...</regulation>
      #   <subjectType code="person" classificationCode="P"/>
      #   <nameAlias ...>...</nameAlias>
      #   <citizenship ...>...</citizenship>
      #   <birthdate ...>...</birthdate>
      #   <address ...>...</address>
      #   <identification ...>...</identification>
      # </sanctionEntity>
      class SanctionEntity < Lutaml::Model::Serializable
        attribute :eu_reference_number, :string
        attribute :logical_id, :string
        attribute :designation_details, :string
        attribute :united_nation_id, :string
        attribute :remark, :string
        attribute :regulations, Regulation, collection: true
        attribute :subject_type, SubjectType
        attribute :name_aliases, NameAlias, collection: true
        attribute :citizenships, Citizenship, collection: true
        attribute :birthdates, Birthdate, collection: true
        attribute :addresses, Address, collection: true
        attribute :identifications, Identification, collection: true

        xml do
          root 'sanctionEntity'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'euReferenceNumber', to: :eu_reference_number
          map_attribute 'logicalId', to: :logical_id
          map_attribute 'designationDetails', to: :designation_details
          map_attribute 'unitedNationId', to: :united_nation_id
          map_element 'remark', to: :remark
          map_element 'regulation', to: :regulations
          map_element 'subjectType', to: :subject_type
          map_element 'nameAlias', to: :name_aliases
          map_element 'citizenship', to: :citizenships
          map_element 'birthdate', to: :birthdates
          map_element 'address', to: :addresses
          map_element 'identification', to: :identifications
        end

        yaml do
          map 'eu_reference_number', to: :eu_reference_number
          map 'logical_id', to: :logical_id
          map 'designation_details', to: :designation_details
          map 'united_nation_id', to: :united_nation_id
          map 'remark', to: :remark
          map 'regulations', to: :regulations
          map 'subject_type', to: :subject_type
          map 'name_aliases', to: :name_aliases
          map 'citizenships', to: :citizenships
          map 'birthdates', to: :birthdates
          map 'addresses', to: :addresses
          map 'identifications', to: :identifications
        end

        # Helper methods
        def entity_type
          subject_type&.code || 'organization'
        end

        def person?
          entity_type == 'person'
        end

        def organization?
          entity_type != 'person'
        end

        def primary_name
          name_aliases.first&.whole_name
        end

        def primary_regulation
          regulations&.first
        end

        def programme
          primary_regulation&.programme
        end

        def gender
          name_aliases.first&.gender
        end

        def nationalities
          return [] if citizenships.nil?

          citizenships.map(&:country_description).compact
        end

        def primary_birthdate
          birthdates.first
        end
      end
    end
  end
end
