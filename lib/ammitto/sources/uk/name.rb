# frozen_string_literal: true

module Ammitto
  module Sources
    module Uk
      # Name variant for UK designation
      #
      # UK uses Name1 through Name6 for different name parts:
      # - Name1: First name / given name
      # - Name6: Full name (primary identifier)
      #
      # @example
      #   name = Ammitto::Sources::Uk::Name.from_xml(name_xml)
      #   puts name.name6      # Full name
      #   puts name.name_type  # "Primary Name" or "Alias"
      #
      class Name < Lutaml::Model::Serializable
        attribute :name1, :string
        attribute :name2, :string
        attribute :name3, :string
        attribute :name4, :string
        attribute :name5, :string
        attribute :name6, :string
        attribute :name_type, :string
        attribute :alias_strength, :string

        xml do
          root 'Name'

          map_element 'Name1', to: :name1
          map_element 'Name2', to: :name2
          map_element 'Name3', to: :name3
          map_element 'Name4', to: :name4
          map_element 'Name5', to: :name5
          map_element 'Name6', to: :name6
          map_element 'NameType', to: :name_type
          map_element 'AliasStrength', to: :alias_strength
        end

        yaml do
          map 'name1', to: :name1
          map 'name2', to: :name2
          map 'name3', to: :name3
          map 'name4', to: :name4
          map 'name5', to: :name5
          map 'name6', to: :name6
          map 'name_type', to: :name_type
          map 'alias_strength', to: :alias_strength
        end

        # Check if this is the primary name
        # @return [Boolean]
        def primary_name?
          name_type == 'Primary Name'
        end

        # Get the full name (prioritize Name6)
        # @return [String, nil]
        def full_name
          name6 || name1
        end

        # Get quality indicator
        # @return [String, nil]
        def quality
          alias_strength
        end
      end
    end
  end
end
