# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual alias from UN sanctions
      class IndividualAlias < Lutaml::Model::Serializable
        attribute :quality, :string
        attribute :alias_name, :string

        xml do
          root 'INDIVIDUAL_ALIAS'
          map_element 'QUALITY', to: :quality
          map_element 'ALIAS_NAME', to: :alias_name
        end

        yaml do
          map 'quality', to: :quality
          map 'alias_name', to: :alias_name
        end
      end
    end
  end
end
