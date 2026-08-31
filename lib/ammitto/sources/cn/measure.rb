# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Measure from YAML
      class Measure < Lutaml::Model::Serializable
        attribute :type, :string, collection: true
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'type', to: :type
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end

        # Get Chinese description
        # @return [String, nil]
        def chinese_description
          zh_hans
        end

        # Get English description
        # @return [String, nil]
        def english_description
          en
        end
      end
    end
  end
end
