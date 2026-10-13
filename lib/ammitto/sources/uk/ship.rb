# frozen_string_literal: true

require 'lutaml/model'
require_relative 'xml_text_list'

module Ammitto
  module Sources
    module Uk
      # The <Ship> block inside <ShipDetails>: the vessel facts OFSI
      # publishes for a designated ship.
      class Ship < Lutaml::Model::Serializable
        extend XmlTextList

        attribute :imo_numbers, :string, collection: true
        attribute :current_owner_operators, :string, collection: true
        attribute :previous_owner_operators, :string, collection: true
        attribute :current_believed_flags, :string, collection: true
        attribute :previous_flags, :string, collection: true
        attribute :types_of_ship, :string, collection: true
        attribute :tonnages, :string, collection: true
        attribute :lengths, :string, collection: true
        attribute :years_built, :string, collection: true

        text_list :imo_numbers, 'IMONumber'
        text_list :current_owner_operators, 'CurrentOwnerOperator'
        text_list :previous_owner_operators, 'PreviousOwnerOperator'
        text_list :current_believed_flags, 'CurrentBelievedFlagOfShip'
        text_list :previous_flags, 'PreviousFlag'
        text_list :types_of_ship, 'TypeOfShip'
        text_list :tonnages, 'TonnageOfShip'
        text_list :lengths, 'LengthOfShip'
        text_list :years_built, 'YearBuilt'

        xml do
          root 'Ship'

          map_element 'IMONumbers', to: :imo_numbers,
                                    **XmlTextList.handlers(:imo_numbers)
          map_element 'CurrentOwnerOperators', to: :current_owner_operators,
                                               **XmlTextList.handlers(:current_owner_operators)
          map_element 'PreviousOwnerOperators', to: :previous_owner_operators,
                                                **XmlTextList.handlers(:previous_owner_operators)
          map_element 'CurrentBelievedFlagOfShips', to: :current_believed_flags,
                                                    **XmlTextList.handlers(:current_believed_flags)
          map_element 'PreviousFlags', to: :previous_flags,
                                       **XmlTextList.handlers(:previous_flags)
          map_element 'TypeOfShipDetails', to: :types_of_ship,
                                           **XmlTextList.handlers(:types_of_ship)
          map_element 'TonnageOfShipDetails', to: :tonnages,
                                              **XmlTextList.handlers(:tonnages)
          map_element 'LengthOfShipDetails', to: :lengths,
                                             **XmlTextList.handlers(:lengths)
          map_element 'YearsBuilt', to: :years_built,
                                    **XmlTextList.handlers(:years_built)
        end

        key_value do
          map 'imo_numbers', to: :imo_numbers
          map 'current_owner_operators', to: :current_owner_operators
          map 'previous_owner_operators', to: :previous_owner_operators
          map 'current_believed_flags', to: :current_believed_flags
          map 'previous_flags', to: :previous_flags
          map 'types_of_ship', to: :types_of_ship
          map 'tonnages', to: :tonnages
          map 'lengths', to: :lengths
          map 'years_built', to: :years_built
        end
      end
    end
  end
end
