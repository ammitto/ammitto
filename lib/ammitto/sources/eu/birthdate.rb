# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Birthdate information from EU sanctions
      #
      # Example XML:
      # <birthdate circa="false" calendarType="GREGORIAN" city="al-Awja, near Tikrit"
      #            zipCode="" birthdate="1937-04-28" dayOfMonth="28" monthOfYear="4"
      #            year="1937" region="" place="" countryIso2Code="IQ"
      #            countryDescription="IRAQ" regulationLanguage="en" logicalId="14">
      #   <regulationSummary .../>
      # </birthdate>
      class Birthdate < Lutaml::Model::Serializable
        attribute :birthdate, :string
        attribute :circa, :boolean
        attribute :calendar_type, :string
        attribute :day_of_month, :integer
        attribute :month_of_year, :integer
        attribute :year, :integer
        attribute :city, :string
        attribute :region, :string
        attribute :place, :string
        attribute :zip_code, :string
        attribute :country_iso2_code, :string
        attribute :country_description, :string
        attribute :regulation_language, :string
        attribute :logical_id, :string
        attribute :regulation_summaries, RegulationSummary, collection: true

        xml do
          root 'birthdate'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'birthdate', to: :birthdate
          map_attribute 'circa', to: :circa
          map_attribute 'calendarType', to: :calendar_type
          map_attribute 'dayOfMonth', to: :day_of_month
          map_attribute 'monthOfYear', to: :month_of_year
          map_attribute 'year', to: :year
          map_attribute 'city', to: :city
          map_attribute 'region', to: :region
          map_attribute 'place', to: :place
          map_attribute 'zipCode', to: :zip_code
          map_attribute 'countryIso2Code', to: :country_iso2_code
          map_attribute 'countryDescription', to: :country_description
          map_attribute 'regulationLanguage', to: :regulation_language
          map_attribute 'logicalId', to: :logical_id
          map_element 'regulationSummary', to: :regulation_summaries
        end

        yaml do
          map 'birthdate', to: :birthdate
          map 'circa', to: :circa
          map 'calendar_type', to: :calendar_type
          map 'day_of_month', to: :day_of_month
          map 'month_of_year', to: :month_of_year
          map 'year', to: :year
          map 'city', to: :city
          map 'region', to: :region
          map 'place', to: :place
          map 'zip_code', to: :zip_code
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
