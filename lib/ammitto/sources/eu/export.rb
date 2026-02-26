# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Root element of EU sanctions XML
      #
      # Example XML:
      # <export generationDate="2026-02-02T17:26:53.906+01:00" globalFileId="180460">
      #   <sanctionEntity ...>...</sanctionEntity>
      # </export>
      class Export < Lutaml::Model::Serializable
        attribute :generation_date, :string
        attribute :global_file_id, :integer
        attribute :sanction_entities, SanctionEntity, collection: true

        xml do
          root 'export'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'generationDate', to: :generation_date
          map_attribute 'globalFileId', to: :global_file_id
          map_element 'sanctionEntity', to: :sanction_entities
        end

        yaml do
          map 'generation_date', to: :generation_date
          map 'global_file_id', to: :global_file_id
          map 'sanction_entities', to: :sanction_entities
        end
      end
    end
  end
end
