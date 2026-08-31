# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Localized title entry from YAML
      class LocalizedTitleEntry < Lutaml::Model::Serializable
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end
      end
    end
  end
end
