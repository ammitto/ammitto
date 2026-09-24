# frozen_string_literal: true

require 'lutaml/model'
require_relative 'source_provenance'

module Ammitto
  module Ontology
    module ValueObjects
      # HarmonizedBirthInfo represents birth information with provenance
      # from multiple sources.
      #
      class HarmonizedBirthInfo < Lutaml::Model::Serializable
        attribute :date, :date
        attribute :year, :string
        attribute :circa, :boolean, default: false
        attribute :city, :string
        attribute :region, :string
        attribute :country, :string
        attribute :country_iso_code, :string
        attribute :sources, SourceProvenance, collection: true

        json do
          map :date, to: :date
          map :year, to: :year
          map :circa, to: :circa
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :sources, to: :sources
        end

        yaml do
          map :date, to: :date
          map :year, to: :year
          map :circa, to: :circa
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :sources, to: :sources
        end
      end
    end
  end
end
