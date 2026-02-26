# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual document from UN sanctions
      class IndividualDocument < Lutaml::Model::Serializable
        attribute :type_of_document, :string
        attribute :number, :string
        attribute :issuing_country, :string
        attribute :note, :string

        xml do
          root 'INDIVIDUAL_DOCUMENT'
          map_element 'TYPE_OF_DOCUMENT', to: :type_of_document
          map_element 'NUMBER', to: :number
          map_element 'ISSUING_COUNTRY', to: :issuing_country
          map_element 'NOTE', to: :note
        end

        yaml do
          map 'type_of_document', to: :type_of_document
          map 'number', to: :number
          map 'issuing_country', to: :issuing_country
          map 'note', to: :note
        end
      end
    end
  end
end
