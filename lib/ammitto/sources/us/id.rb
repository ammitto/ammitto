# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # ID entry
      class Id < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :id_type, :string
        attribute :id_number, :string
        attribute :id_country, :string
        attribute :issue_date, :string
        attribute :expiration_date, :string

        xml do
          root 'id'
          map_element 'uid', to: :uid
          map_element 'idType', to: :id_type
          map_element 'idNumber', to: :id_number
          map_element 'idCountry', to: :id_country
          map_element 'issueDate', to: :issue_date
          map_element 'expirationDate', to: :expiration_date
        end

        yaml do
          map 'uid', to: :uid
          map 'id_type', to: :id_type
          map 'id_number', to: :id_number
          map 'id_country', to: :id_country
          map 'issue_date', to: :issue_date
          map 'expiration_date', to: :expiration_date
        end
      end
    end
  end
end
