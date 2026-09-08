# frozen_string_literal: true

require 'lutaml/model'
require_relative 'alias_strength'
require_relative 'name_type'
require_relative 'script'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Name variant with type, script, and strength information
      class Name < Lutaml::Model::Serializable
        attribute :text, :string           # The name text
        attribute :name_type, :string      # Primary Name, Original Script, Alias
        attribute :script, :string         # ISO 15924 script code
        attribute :alias_strength, :string # Strong, Weak, or nil

        def primary?
          name_type == NameType::PRIMARY
        end

        def original_script?
          name_type == NameType::ORIGINAL_SCRIPT
        end

        def alias?
          name_type == NameType::ALIAS
        end

        def strong_alias?
          alias? && alias_strength == AliasStrength::STRONG
        end

        def weak_alias?
          alias? && alias_strength == AliasStrength::WEAK
        end

        def self.from_csv(name_text, name_type, alias_strength)
          new(
            text: name_text,
            name_type: NameType.from_csv(name_type),
            script: Script.detect(name_text),
            alias_strength: AliasStrength.from_csv(alias_strength)
          )
        end
      end
    end
  end
end
