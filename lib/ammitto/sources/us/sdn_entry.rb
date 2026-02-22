# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # SDN Entry (main entity record)
      #
      # Example XML:
      # <sdnEntry>
      #   <uid>36</uid>
      #   <lastName>AEROCARIBBEAN AIRLINES</lastName>
      #   <sdnType>Entity</sdnType>
      #   <programList><program>CUBA</program></programList>
      #   <akaList>...</akaList>
      #   <addressList>...</addressList>
      # </sdnEntry>
      class SdnEntry < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :first_name, :string
        attribute :last_name, :string
        attribute :sdn_type, :string
        attribute :program_list, ProgramList
        attribute :aka_list, AkaList
        attribute :address_list, AddressList
        attribute :id_list, IdList
        attribute :date_of_birth_list, DateOfBirthList
        attribute :place_of_birth_list, PlaceOfBirthList
        attribute :remarks, :string
        attribute :title, :string
        attribute :nationality_list, ProgramList # Same structure as programList

        xml do
          root 'sdnEntry'
          namespace 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/XML', nil

          map_element 'uid', to: :uid
          map_element 'firstName', to: :first_name
          map_element 'lastName', to: :last_name
          map_element 'sdnType', to: :sdn_type
          map_element 'programList', to: :program_list
          map_element 'akaList', to: :aka_list
          map_element 'addressList', to: :address_list
          map_element 'idList', to: :id_list
          map_element 'dateOfBirthList', to: :date_of_birth_list
          map_element 'placeOfBirthList', to: :place_of_birth_list
          map_element 'remarks', to: :remarks
          map_element 'title', to: :title
          map_element 'nationalityList', to: :nationality_list
        end

        yaml do
          map 'uid', to: :uid
          map 'first_name', to: :first_name
          map 'last_name', to: :last_name
          map 'sdn_type', to: :sdn_type
          map 'program_list', to: :program_list
          map 'aka_list', to: :aka_list
          map 'address_list', to: :address_list
          map 'id_list', to: :id_list
          map 'date_of_birth_list', to: :date_of_birth_list
          map 'place_of_birth_list', to: :place_of_birth_list
          map 'remarks', to: :remarks
          map 'title', to: :title
          map 'nationality_list', to: :nationality_list
        end

        # Helper methods
        def full_name
          [first_name, last_name].compact.join(' ')
        end

        def primary_name
          full_name.to_s.strip.empty? ? last_name : full_name
        end

        def entity_type
          case sdn_type.to_s.strip
          when /Individual/i then 'person'
          when /Vessel/i then 'vessel'
          when /Aircraft/i then 'aircraft'
          else 'organization'
          end
        end

        def person?
          entity_type == 'person'
        end

        def programs
          program_list&.programs || []
        end

        def aliases
          aka_list&.items || []
        end

        def addresses
          address_list&.items || []
        end

        def identifications
          id_list&.items || []
        end

        def dates_of_birth
          date_of_birth_list&.items || []
        end

        def places_of_birth
          place_of_birth_list&.items || []
        end
      end
    end
  end
end
