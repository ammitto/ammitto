# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../utils/presence'
require_relative 'designation'

module Ammitto
  module Sources
    module EuVessels
      # Vessel represents one vessel on the EU designated vessels list,
      # with every designation DMA lists for it.
      #
      class Vessel < Lutaml::Model::Serializable
        attribute :vessel_name, :string
        attribute :imo_number, :string
        attribute :designations, Designation, collection: true
        # Read only: files fetched before designations were recorded carry
        # the date alone at the top level (see #designations_or_legacy).
        attribute :date_of_application, :date

        # Create Vessel from row data hash
        # @param data [Hash] row data
        # @return [Vessel]
        def self.from_row_data(data)
          new(
            vessel_name: data['vessel_name']&.to_s,
            imo_number: data['imo_number']&.to_s&.strip,
            designations: [
              Designation.new(
                date_of_application: data['date_of_application'],
                subject_to: data['subject_to']&.to_s
              )
            ]
          )
        end

        # Stable local identifier for filenames and harmonized IRIs: the
        # IMO number when DMA gives one. A DPRK vessel can have none (the
        # regulation lists MIN NING DE YOU 078 with IMO "Does not exist"),
        # and then its identity is a slug of its name, the same slug the
        # UN vessels source mints for that vessel, so both sources name it
        # alike. A constant fallback such as "IMO-" would give every such
        # vessel one filename and one IRI.
        # @return [String, nil]
        def local_id
          imo = imo_number.to_s.strip
          return imo unless imo.empty?

          slug = vessel_name.to_s.downcase.gsub(/[^a-z0-9]+/, '-')
                            .gsub(/\A-+|-+\z/, '')
          slug.empty? ? nil : slug
        end

        # The designations this record states. A file fetched before the
        # workbook's "Subject to" column was read holds one date and no
        # measure; it is read as one designation whose Subject to is
        # unknown, so its date is still published and nothing is guessed.
        # @return [Array<Designation>]
        def designations_or_legacy
          return designations if Array(designations).any?
          return [] if date_of_application.nil?

          [Designation.new(date_of_application: date_of_application)]
        end

        # The identifier ItemMapper names this record's file after.
        # @return [String, nil]
        def identifier
          Ammitto::Utils::Presence.presence(local_id)
        end
      end
    end
  end
end
