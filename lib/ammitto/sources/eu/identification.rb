# frozen_string_literal: true

require 'lutaml/model'

require_relative 'export_namespace'
require_relative 'regulation_summary'

module Ammitto
  module Sources
    module Eu
      # Identification document information from EU sanctions
      #
      # Example XML:
      # <identification identificationTypeCode="passport" number="123456789"
      #                countryIso2Code="IQ" regulationLanguage="en" logicalId="1">
      #   <regulationSummary .../>
      # </identification>
      class Identification < Lutaml::Model::Serializable
        attribute :identification_type_code, :string
        attribute :number, :string
        attribute :country_iso2_code, :string
        attribute :regulation_language, :string
        attribute :logical_id, :string
        attribute :valid_to, :string
        attribute :issue_date, :string
        attribute :issued_by, :string
        attribute :regulation_summaries, RegulationSummary, collection: true

        xml do
          root 'identification'
          namespace ExportNamespace

          map_attribute 'identificationTypeCode', to: :identification_type_code
          map_attribute 'number', to: :number
          map_attribute 'countryIso2Code', to: :country_iso2_code
          map_attribute 'regulationLanguage', to: :regulation_language
          map_attribute 'logicalId', to: :logical_id
          map_attribute 'validTo', to: :valid_to
          map_attribute 'issueDate', to: :issue_date
          map_attribute 'issuedBy', to: :issued_by
          map_element 'regulationSummary', to: :regulation_summaries
        end

        yaml do
          map 'identification_type_code', to: :identification_type_code
          map 'number', to: :number
          map 'country_iso2_code', to: :country_iso2_code
          map 'regulation_language', to: :regulation_language
          map 'logical_id', to: :logical_id
          map 'valid_to', to: :valid_to
          map 'issue_date', to: :issue_date
          map 'issued_by', to: :issued_by
          map 'regulation_summaries', to: :regulation_summaries
        end
      end
    end
  end
end
