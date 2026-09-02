# frozen_string_literal: true

require 'lutaml/model'
require_relative 'document_type_entry'

module Ammitto
  module Sources
    module Cn
      # Source model for document-types.yml
      #
      # @example Parsing document-types.yml
      #   data = YAML.load_file('sources/supporting/document-types.yml')
      #   types = DocumentTypesSource.from_hash(data)
      #   types.document_types.each do |type|
      #     puts "#{type.id}: #{type.name.en}"
      #   end
      #
      class DocumentTypesSource < Lutaml::Model::Serializable
        attribute :document_types, DocumentTypeEntry, collection: true

        key_value do
          map 'document_types', to: :document_types
        end

        # Get all document types as ontology models
        # @return [Array<Ammitto::Ontology::DocumentType>]
        def to_document_types
          document_types.map(&:to_document_type)
        end
      end
    end
  end
end
