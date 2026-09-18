# frozen_string_literal: true

require 'lutaml/model'
require_relative 'source_provenance'

module Ammitto
  module Ontology
    module ValueObjects
      # HarmonizedIdentification represents identification with provenance
      #
      class HarmonizedIdentification < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :document_type, :string
        attribute :number, :string
        attribute :issuing_country, :string
        attribute :note, :string
        attribute :sources, SourceProvenance, collection: true

        json do
          map :type, to: :type
          map :document_type, to: :document_type
          map :number, to: :number
          map :issuing_country, to: :issuing_country
          map :note, to: :note
          map :sources, to: :sources
        end

        yaml do
          map :type, to: :type
          map :document_type, to: :document_type
          map :number, to: :number
          map :issuing_country, to: :issuing_country
          map :note, to: :note
          map :sources, to: :sources
        end
      end
    end
  end
end
