# frozen_string_literal: true

require 'lutaml/model'
require_relative 'source_provenance'

module Ammitto
  module Ontology
    module ValueObjects
      # HarmonizedNationality represents nationality with provenance
      #
      class HarmonizedNationality < Lutaml::Model::Serializable
        attribute :country, :string
        attribute :country_iso_code, :string
        attribute :sources, SourceProvenance, collection: true

        json do
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :sources, to: :sources
        end

        yaml do
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :sources, to: :sources
        end
      end
    end
  end
end
