# frozen_string_literal: true

require 'lutaml/model'
require_relative 'date_normalizer'

module Ammitto
  module Sources
    module Uk
      # Root element for UK sanctions list XML
      #
      # Maps to the <Designations> root element in the UK XML schema.
      #
      # @example Parsing from XML
      #   designations = Ammitto::Sources::Uk::Designations.from_xml(xml_content)
      #   puts designations.date_generated
      #   designations.designations.each do |d|
      #     puts d.unique_id
      #   end
      #
      class Designations < Lutaml::Model::Serializable
        include DateNormalizer

        attribute :date_generated, :string
        attribute :designations, Designation, collection: true

        xml do
          root 'Designations'
          # Elements are in default namespace (no prefix)
          # The XML declares xsi/xsd namespaces for schema but doesn't use them

          map_element 'DateGenerated', to: :date_generated
          map_element 'Designation', to: :designations
        end

        yaml do
          map 'date_generated', to: :date_generated
          map 'designations', to: :designations
        end

        # Get date_generated in normalized ISO format (YYYY-MM-DD)
        # @return [String, nil]
        def date_generated
          normalize_date(@date_generated)
        end
      end
    end
  end
end

require_relative 'designation'
