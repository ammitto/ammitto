# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Uk
      # One <NationalIdentifier> entry of an individual's
      # <NationalIdentifierDetails>
      class NationalIdentifier < Lutaml::Model::Serializable
        attribute :number, :string
        attribute :additional_information, :string

        xml do
          root 'NationalIdentifier'
          map_element 'NationalIdentifierNumber', to: :number
          map_element 'NationalIdentifierAdditionalInformation',
                      to: :additional_information
        end

        key_value do
          map 'number', to: :number
          map 'additional_information', to: :additional_information
        end
      end
    end
  end
end
