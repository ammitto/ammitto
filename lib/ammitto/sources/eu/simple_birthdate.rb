# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
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
    end
  end
end
