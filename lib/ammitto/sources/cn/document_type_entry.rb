# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../ontology/document_type'
require_relative 'localized_name_entry'

module Ammitto
  module Sources
    module Cn
      # Document type entry from YAML
      class DocumentTypeEntry < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :name, LocalizedNameEntry

        key_value do
          map 'id', to: :id
          map 'name', to: :name
        end

        # Convert to DocumentType ontology model
        # @return [Ammitto::Ontology::DocumentType]
        def to_document_type
          Ammitto::Ontology::DocumentType.new(
            id: id,
            name: name&.to_localized_strings || []
          )
        end
      end
    end
  end
end
