# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Root element of UN consolidated sanctions list
      #
      # Example XML:
      # <CONSOLIDATED_LIST dateGenerated="2026-02-22T00:00:01.615Z">
      #   <INDIVIDUALS>...</INDIVIDUALS>
      #   <ENTITIES>...</ENTITIES>
      # </CONSOLIDATED_LIST>
      class ConsolidatedList < Lutaml::Model::Serializable
        attribute :date_generated, :string
        attribute :individuals, IndividualsWrapper
        attribute :entities, EntitiesWrapper

        xml do
          root 'CONSOLIDATED_LIST'
          map_attribute 'dateGenerated', to: :date_generated
          map_element 'INDIVIDUALS', to: :individuals
          map_element 'ENTITIES', to: :entities
        end

        yaml do
          map 'date_generated', to: :date_generated
          map 'individuals', to: :individuals
          map 'entities', to: :entities
        end

        # Helper methods
        def all_individuals
          individuals&.items || []
        end

        def all_entities
          entities&.items || []
        end

        def total_count
          all_individuals.count + all_entities.count
        end
      end
    end
  end
end
