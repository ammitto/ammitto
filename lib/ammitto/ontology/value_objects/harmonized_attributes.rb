# frozen_string_literal: true

require 'lutaml/model'

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
