# frozen_string_literal: true

require 'lutaml/model'
require_relative 'record'

module Ammitto
  module Sources
    module Ca
      # Canadian Consolidated Autonomous Sanctions List (XML)
      #
      # The actual XML format uses <data-set> as root element with <record>
      # children. Each record represents either an individual or entity.
      #
      # @example Parsing from XML
      #   list = Ca::SanctionsList.from_xml(xml_content)
      #   list.records.each do |record|
      #     puts record.full_name
      #   end
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :records, Record, collection: true

        xml do
          root 'data-set'
          map_element 'record', to: :records
        end

        # Get all individuals (records with names)
        # @return [Array<Record>]
        def individuals
          records.select(&:individual?)
        end

        # Get all entities (records without personal names)
        # @return [Array<Record>]
        def entities
          records.reject(&:individual?)
        end
      end
    end
  end
end
