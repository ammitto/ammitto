# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Uk
      # Simple name for processed YAML data
      class ProcessedName < Lutaml::Model::Serializable
        attribute :full_name, :string
        attribute :is_primary, :boolean, default: false
        attribute :script, :string, default: 'Latn'

        yaml do
          map 'full_name', to: :full_name
          map 'is_primary', to: :is_primary
          map 'script', to: :script
        end

        # Alias for transformer compatibility
        def primary?
          is_primary
        end

        def text
          full_name
        end
      end

      # Simple source reference for processed YAML data
      class ProcessedSourceReference < Lutaml::Model::Serializable
        attribute :source_code, :string
        attribute :reference_number, :string

        yaml do
          map 'source_code', to: :source_code
          map 'reference_number', to: :reference_number
        end
      end

      # Simple details container
      class ProcessedDetails < Lutaml::Model::Serializable
        yaml do
        end
      end

      # Processed entity from UK processed YAML files
      #
      # This model matches the simplified YAML format produced by the
      # fetch command, not the original UK OFSI XML format.
      #
      # @example
      #   entity = ProcessedEntity.from_yaml(yaml_content)
      #   puts entity.type  # "person", "organization", or "vessel"
      #   entity.names.each { |n| puts n.full_name }
      #
      class ProcessedEntity < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :type, :string
        attribute :names, ProcessedName, collection: true
        attribute :source_references, ProcessedSourceReference,
                  collection: true
        attribute :person_details, ProcessedDetails
        attribute :organization_details, ProcessedDetails
        attribute :vessel_details, ProcessedDetails
        attribute :remarks, :string

        yaml do
          map 'id', to: :id
          map 'type', to: :type
          map 'names', to: :names
          map 'source_references', to: :source_references
          map 'person_details', to: :person_details
          map 'organization_details', to: :organization_details
          map 'vessel_details', to: :vessel_details
          map 'remarks', to: :remarks
        end

        # Check if this is an individual
        # @return [Boolean]
        def individual?
          type == 'person'
        end

        # Check if this is an entity (organization)
        # @return [Boolean]
        def entity?
          type == 'organization'
        end

        # Check if this is a vessel
        # @return [Boolean]
        def vessel?
          type == 'vessel'
        end

        # Get primary name
        # @return [ProcessedName, nil]
        def primary_name
          names.find(&:primary?)
        end

        # Get all aliases (non-primary names)
        # @return [Array<ProcessedName>]
        def aliases
          names.reject(&:primary?)
        end

        # Get the reference number from source references
        # @return [String, nil]
        def reference_number
          source_references.first&.reference_number
        end

        # Get entity type for harmonization
        # @return [String]
        def entity_type
          type
        end
      end
    end
  end
end
