# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Jp
      # SanctionsList represents the Japan End-User List
      #
      # Note: JP data is manually curated in data-jp (announcement YAML
      # under sources/sanction-lists, converted with data-jp's own
      # scripts). This class only builds a list from already-converted
      # structured data; it cannot parse a METI publication itself.
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

        # Refuse to parse a PDF. This used to be a placeholder that
        # printed a note and returned an empty list, so `fetch jp`
        # reported success while saving zero files. There is no PDF
        # ingestion: raising keeps any caller from mistaking an empty
        # list for a harvest.
        # @param _pdf_path [String] path to PDF file
        # @raise [NotImplementedError] always
        def self.from_pdf(_pdf_path)
          raise NotImplementedError,
                'Jp::SanctionsList cannot parse PDFs; JP data is ' \
                'manually curated in data-jp. Use from_converted_data ' \
                'with already-converted structured data.'
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
