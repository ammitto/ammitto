# frozen_string_literal: true

require 'lutaml/model'
require_relative 'source_provenance'

module Ammitto
  module Ontology
    module ValueObjects
      # HarmonizedAddress represents address with provenance
      #
      class HarmonizedAddress < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :state, :string
        attribute :country, :string
        attribute :country_iso_code, :string
        attribute :postal_code, :string
        attribute :sources, SourceProvenance, collection: true

        json do
          map :street, to: :street
          map :city, to: :city
          map :state, to: :state
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :postal_code, to: :postal_code
          map :sources, to: :sources
        end

        yaml do
          map :street, to: :street
          map :city, to: :city
          map :state, to: :state
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :postal_code, to: :postal_code
          map :sources, to: :sources
        end
      end
    end
  end
end
