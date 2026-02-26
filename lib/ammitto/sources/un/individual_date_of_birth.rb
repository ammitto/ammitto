# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual date of birth from UN sanctions
      class IndividualDateOfBirth < Lutaml::Model::Serializable
        attribute :type_of_date, :string
        attribute :date, :string
        attribute :year, :integer

        xml do
          root 'INDIVIDUAL_DATE_OF_BIRTH'
          map_element 'TYPE_OF_DATE', to: :type_of_date
          map_element 'DATE', to: :date
          map_element 'YEAR', to: :year
        end

        yaml do
          map 'type_of_date', to: :type_of_date
          map 'date', to: :date
          map 'year', to: :year
        end
      end
    end
  end
end
