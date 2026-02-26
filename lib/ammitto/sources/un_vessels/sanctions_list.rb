# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module UnVessels
      # SanctionsList represents the UN Security Council Designated Vessels List
      #
      # Note: The UN Designated Vessels List is published as a PDF document.
      # This class provides methods for parsing the data after manual conversion
      # from PDF to structured format.
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :vessels, Vessel, collection: true
        attribute :fetched_at, :string
        attribute :source, :string

        # Create SanctionsList from manually converted data
        # @param data [Hash] structured data from PDF conversion
        # @return [SanctionsList]
        def self.from_converted_data(data)
          list = new
          list.source = 'un_vessels'
          list.fetched_at = Time.now.utc.iso8601
          list.vessels = (data['vessels'] || []).map do |vessel_data|
            Vessel.from_hash(vessel_data)
          end
          list
        end

        # Create SanctionsList from PDF (placeholder - requires manual conversion)
        # @param _pdf_path [String] path to PDF file
        # @return [SanctionsList]
        def self.from_pdf(_pdf_path)
          puts 'Note: UN Designated Vessels List is PDF-based and requires manual conversion'
          puts 'Please convert the PDF to structured data and use from_converted_data'

          new.tap do |list|
            list.source = 'un_vessels'
            list.fetched_at = Time.now.utc.iso8601
            list.vessels = []
          end
        end

        # Get all vessels
        # @return [Array<Vessel>]
        def all_vessels
          vessels
        end

        # Get count of vessels
        # @return [Integer]
        def count
          vessels.length
        end
      end
    end
  end
end
