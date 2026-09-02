# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Instrument reference from YAML (reused for modifications)
      class ModificationInstrument < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :law, :string
        attribute :articles, :string, collection: true

        key_value do
          map 'id', to: :id
          map 'law', to: :law
          map 'articles', to: :articles
        end
      end
    end
  end
end
