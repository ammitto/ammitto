# frozen_string_literal: true

require 'lutaml/model'
require_relative 'xml_text_list'

module Ammitto
  module Sources
    module Uk
      # The <Entity> block inside <EntityDetails>: what OFSI publishes about
      # a designated organisation beyond its names and addresses.
      class LegalEntity < Lutaml::Model::Serializable
        extend XmlTextList

        attribute :business_registration_numbers, :string, collection: true
        attribute :types_of_entity, :string, collection: true
        attribute :parent_companies, :string, collection: true
        attribute :subsidiaries, :string, collection: true

        text_list :business_registration_numbers, 'BusinessRegistrationNumber'
        text_list :types_of_entity, 'TypeOfEntity'
        text_list :parent_companies, 'ParentCompany'
        text_list :subsidiaries, 'Subsidiary'

        xml do
          root 'Entity'

          map_element 'BusinessRegistrationNumbers', to: :business_registration_numbers,
                                                     **XmlTextList.handlers(:business_registration_numbers)
          map_element 'TypeOfEntities', to: :types_of_entity,
                                        **XmlTextList.handlers(:types_of_entity)
          map_element 'ParentCompanies', to: :parent_companies,
                                         **XmlTextList.handlers(:parent_companies)
          map_element 'Subsidiaries', to: :subsidiaries,
                                      **XmlTextList.handlers(:subsidiaries)
        end

        key_value do
          map 'business_registration_numbers', to: :business_registration_numbers
          map 'types_of_entity', to: :types_of_entity
          map 'parent_companies', to: :parent_companies
          map 'subsidiaries', to: :subsidiaries
        end
      end
    end
  end
end
