# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Uk
      # One <Passport> entry of an individual's <PassportDetails>
      class Passport < Lutaml::Model::Serializable
        attribute :number, :string
        attribute :additional_information, :string

        xml do
          root 'Passport'
          map_element 'PassportNumber', to: :number
          map_element 'PassportAdditionalInformation',
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
