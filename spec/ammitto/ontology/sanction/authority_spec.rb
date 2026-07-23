# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::Sanction::Authority do
  it 'carries id, name, country code, and url' do
    authority = described_class.new(id: 'ch', name: 'Switzerland (SECO)',
                                    country_code: 'CH', url: 'https://www.seco.admin.ch')
    expect(authority.id).to eq('ch')
    expect(authority.country_code).to eq('CH')
  end

  describe '#to_hash' do
    it 'omits nil fields' do
      expect(described_class.new(id: 'ch', name: 'SECO').to_hash)
        .to eq({ id: 'ch', name: 'SECO' })
    end
  end

  it 'round-trips through YAML' do
    authority = described_class.new(id: 'un', name: 'United Nations', country_code: 'UN')
    restored = described_class.from_yaml(authority.to_yaml)
    expect(restored.to_hash).to eq(authority.to_hash)
  end
end
