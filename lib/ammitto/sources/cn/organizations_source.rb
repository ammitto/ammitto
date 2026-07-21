# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Organization entry from YAML
      class OrganizationEntry < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :name, LocalizedNameEntry
        attribute :parent_id, :string
        attribute :type, :string
        attribute :url, :string

        key_value do
          map 'id', to: :id
          map 'name', to: :name
          map 'parent_id', to: :parent_id
          map 'type', to: :type
          map 'url', to: :url
        end

        # Convert to Organization ontology model
        # @return [Ammitto::Ontology::Organization]
        def to_organization
          Ammitto::Ontology::Organization.new(
            id: id,
            name: name&.to_localized_strings || [],
            parent_id: parent_id,
            type: type,
            url: url
          )
        end
      end

      # Source model for organizations.yml
      #
      # @example Parsing organizations.yml
      #   data = YAML.load_file('sources/supporting/organizations.yml')
      #   orgs = OrganizationsSource.from_hash(data)
      #   orgs.organizations.each do |org|
      #     puts "#{org.id}: #{org.name.en}"
      #   end
      #
      class OrganizationsSource < Lutaml::Model::Serializable
        attribute :organizations, OrganizationEntry, collection: true

        key_value do
          map 'organizations', to: :organizations
        end

        # Get all organizations as ontology models
        # @return [Array<Ammitto::Ontology::Organization>]
        def to_organizations
          organizations.map(&:to_organization)
        end
      end
    end
  end
end
