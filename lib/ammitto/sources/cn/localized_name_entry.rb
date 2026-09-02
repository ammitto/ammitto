# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../ontology/value_objects/localized_string'

module Ammitto
  module Sources
    module Cn
      # Localized name entry from YAML
      class LocalizedNameEntry < Lutaml::Model::Serializable
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end

        # Convert to LocalizedString
        # @return [Array<Ammitto::Ontology::ValueObjects::LocalizedString>]
        def to_localized_strings
          strings = []
          if zh_hans
            strings << Ammitto::Ontology::ValueObjects::LocalizedString.new(
              value: zh_hans,
              language: 'zh',
              script: 'Hani',
              is_primary: true
            )
          end
          if en
            strings << Ammitto::Ontology::ValueObjects::LocalizedString.new(
              value: en,
              language: 'en',
              script: 'Latn',
              is_primary: false
            )
          end
          strings
        end
      end
    end
  end
end
