# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology/value_objects/source_provenance'

RSpec.describe Ammitto::Ontology::ValueObjects::SourceProvenance do
  describe 'serialization' do
    it 'builds and serializes a fully populated instance without raising' do
      expect do
        provenance = described_class.new(
          source_code: 'uk',
          source_entity_iri: 'https://www.ammitto.org/entity/uk/xxx',
          match_confidence: 0.95,
          contributed_at: Time.new(2026, 1, 1, 12, 0, 0)
        )
        provenance.to_json
      end.not_to raise_error
    end
  end
end
