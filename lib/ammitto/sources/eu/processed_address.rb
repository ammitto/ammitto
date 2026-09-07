# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Simple address for processed data
      class ProcessedAddress < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :state, :string
        attribute :country, :string
        attribute :zip, :string

        yaml do
          map 'street', to: :street
          map 'city', to: :city
          map 'state', to: :state
          map 'country', to: :country
          map 'zip', to: :zip
        end

        def country_description
          country
        end

        def country_iso2_code
          nil
        end

        def region
          state
        end

        def zip_code
          zip
        end
      end
    end
  end
end
