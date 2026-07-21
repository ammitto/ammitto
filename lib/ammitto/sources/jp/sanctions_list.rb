# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Jp
      # SanctionsList represents the Japan End-User List
      #
      # Note: The Japan End-User List is published as a PDF document.
      # This class provides methods for parsing the data after manual conversion
      # from PDF to structured format.
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :entities, Entity, collection: true
        attribute :fetched_at, :string
        attribute :source, :string

        # Create SanctionsList from manually converted data
        # @param data [Hash] structured data from PDF conversion
        # @return [SanctionsList]
        def self.from_converted_data(data)
          list = new
          list.source = 'jp'
          list.fetched_at = Time.now.utc.iso8601
          list.entities = (data['entities'] || []).map do |entity_data|
            Entity.from_hash(entity_data)
          end
          list
        end

        # Create SanctionsList from PDF (placeholder - requires manual conversion)
        # @param _pdf_path [String] path to PDF file
        # @return [SanctionsList]
        def self.from_pdf(_pdf_path)
          puts 'Note: Japan End-User List is PDF-based and requires manual conversion'
          puts 'Please convert the PDF to structured data and use from_converted_data'

          new.tap do |list|
            list.source = 'jp'
            list.fetched_at = Time.now.utc.iso8601
            list.entities = []
          end
        end

        # Get all entities
        # @return [Array<Entity>]
        def all_entities
          entities
        end

        # Get count of entities
        # @return [Integer]
        def count
          entities.length
        end
      end
    end
  end
end
