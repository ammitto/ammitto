# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::Sanction::SanctionRegime do
  it 'carries code, name, and description' do
    regime = described_class.new(code: 'DPRK', name: 'North Korea sanctions',
                                 description: 'UNSC 1718 measures')
    expect(regime.code).to eq('DPRK')
    expect(regime.name).to eq('North Korea sanctions')
  end

  describe '#to_hash' do
    it 'omits nil fields' do
      expect(described_class.new(code: 'DPRK').to_hash).to eq({ code: 'DPRK' })
    end
  end

  it 'round-trips through YAML' do
    regime = described_class.new(code: 'RUSSIA', name: 'Russia/Ukraine measures')
    restored = described_class.from_yaml(regime.to_yaml)
    expect(restored.to_hash).to eq(regime.to_hash)
  end
end
