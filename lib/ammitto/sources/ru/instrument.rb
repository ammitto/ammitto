# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../ontology/value_objects/legal_citation'

module Ammitto
  module Sources
    module Ru
      # The legal instrument an announcement acts under.
      class Instrument < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :law, :string
        attribute :articles, :string, collection: true

        key_value do
          map 'id', to: :id
          map 'law', to: :law
          map 'articles', to: :articles
        end

        # @param instrument_id [String] IRI of the LegalInstrument
        # @return [Ammitto::Ontology::ValueObjects::LegalCitation]
        def to_legal_citation(instrument_id:)
          Ammitto::Ontology::ValueObjects::LegalCitation.new(
            legal_instrument_id: instrument_id,
            articles: articles,
            citation_type: 'legal_basis'
          )
        end
      end
    end
  end
end
