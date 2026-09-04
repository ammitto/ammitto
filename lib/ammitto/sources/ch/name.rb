# frozen_string_literal: true

require 'lutaml/model'
require_relative 'name_part'

module Ammitto
  module Sources
    module Ch
      # Name in Swiss sanctions list
      class Name < Lutaml::Model::Serializable
        attribute :name_type, :string
        attribute :quality, :string
        attribute :lang, :string
        attribute :name_parts, NamePart, collection: true

        xml do
          root 'name'
          map_attribute 'name-type', to: :name_type
          map_attribute 'quality', to: :quality
          map_attribute 'lang', to: :lang
          map_element 'name-part', to: :name_parts
        end

        yaml do
          map 'name_type', to: :name_type
          map 'quality', to: :quality
          map 'lang', to: :lang
          map 'name_parts', to: :name_parts
        end

        # Get full name from name parts
        def full_name
          name_parts.sort_by(&:order).map(&:value).compact.join(' ')
        end
      end
    end
  end
end
