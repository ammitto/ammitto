# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Address information from EU sanctions
      #
      # Example XML:
      # <address street="123 Main St" city="Vienna" region=""
      #          countryIso2Code="AT" countryDescription="AUSTRIA"
      #          zipCode="1010" regulationLanguage="en" logicalId="1">
      #   <regulationSummary .../>
      # </address>
      class Address < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :region, :string
        attribute :country_iso2_code, :string
        attribute :country_description, :string
        attribute :zip_code, :string
        attribute :regulation_language, :string
        attribute :logical_id, :string
        attribute :regulation_summaries, RegulationSummary, collection: true

        xml do
          root 'address'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'street', to: :street
          map_attribute 'city', to: :city
          map_attribute 'region', to: :region
          map_attribute 'countryIso2Code', to: :country_iso2_code
          map_attribute 'countryDescription', to: :country_description
          map_attribute 'zipCode', to: :zip_code
          map_attribute 'regulationLanguage', to: :regulation_language
          map_attribute 'logicalId', to: :logical_id
          map_element 'regulationSummary', to: :regulation_summaries
        end

        yaml do
          map 'street', to: :street
          map 'city', to: :city
          map 'region', to: :region
          map 'country_iso2_code', to: :country_iso2_code
          map 'country_description', to: :country_description
          map 'zip_code', to: :zip_code
          map 'regulation_language', to: :regulation_language
          map 'logical_id', to: :logical_id
          map 'regulation_summaries', to: :regulation_summaries
        end
      end
    end
  end
end
