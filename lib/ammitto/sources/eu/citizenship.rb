# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Citizenship information from EU sanctions
      #
      # Example XML:
      # <citizenship region="" countryIso2Code="IQ" countryDescription="IRAQ"
      #              regulationLanguage="en" logicalId="1">
      #   <regulationSummary .../>
      # </citizenship>
      class Citizenship < Lutaml::Model::Serializable
        attribute :region, :string
        attribute :country_iso2_code, :string
        attribute :country_description, :string
        attribute :regulation_language, :string
        attribute :logical_id, :string
        attribute :regulation_summaries, RegulationSummary, collection: true

        xml do
          root 'citizenship'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'region', to: :region
          map_attribute 'countryIso2Code', to: :country_iso2_code
          map_attribute 'countryDescription', to: :country_description
          map_attribute 'regulationLanguage', to: :regulation_language
          map_attribute 'logicalId', to: :logical_id
          map_element 'regulationSummary', to: :regulation_summaries
        end

        yaml do
          map 'region', to: :region
          map 'country_iso2_code', to: :country_iso2_code
          map 'country_description', to: :country_description
          map 'regulation_language', to: :regulation_language
          map 'logical_id', to: :logical_id
          map 'regulation_summaries', to: :regulation_summaries
        end
      end
    end
  end
end
