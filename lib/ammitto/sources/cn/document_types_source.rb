# frozen_string_literal: true

require 'lutaml/model'

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
