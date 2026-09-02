# frozen_string_literal: true

require 'lutaml/model'
require_relative 'organization_entry'

module Ammitto
  module Sources
    module Cn
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
