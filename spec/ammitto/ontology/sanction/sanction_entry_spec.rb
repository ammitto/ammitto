# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::Sanction::SanctionEntry do
  describe 'status' do
    it 'defaults to active' do
      entry = described_class.new(id: 'e1')
      expect(entry.status).to eq('active')
      expect(entry).to be_active
      expect(entry).not_to be_delisted
    end

    it 'reports delisted when set' do
      entry = described_class.new(id: 'e1', status: 'delisted')
      expect(entry).to be_delisted
      expect(entry).not_to be_active
    end
  end

  describe '#add_status_change' do
    it 'records the full transition in history' do
      entry = described_class.new(id: 'e1')
      entry.add_status_change('suspended', date: Date.new(2026, 1, 1), reason: 'court order')

      expect(entry.status).to eq('suspended')
      expect(entry.status_history.length).to eq(1)
      change = entry.status_history.first
      expect(change.from_status).to eq('active')
      expect(change.to_status).to eq('suspended')
      expect(change.date).to eq(Date.new(2026, 1, 1))
      expect(change.reason).to eq('court order')
    end

    it 'canonicalizes status casing before persisting' do
      entry = described_class.new(id: 'e1')
      entry.add_status_change('DELISTED')
      expect(entry.status).to eq('delisted')
      expect(entry).to be_delisted
      expect(entry.status_history.first.to_status).to eq('delisted')
    end

    it 'rejects blank and unknown statuses without mutating the entry' do
      entry = described_class.new(id: 'e1')
      [nil, '', 'vaporized'].each do |bad|
        expect { entry.add_status_change(bad) }.to raise_error(ArgumentError)
      end
      expect(entry.status).to eq('active')
      expect(entry.status_history).to be_nil
    end
  end

  it 'composes the full ontology graph node' do
    entry = described_class.new(
      id: 'entry/ch/1', entity_id: 'entity/ch/1',
      authority: Ammitto::Ontology::Sanction::Authority.new(id: 'ch', name: 'SECO'),
      regime: Ammitto::Ontology::Sanction::SanctionRegime.new(code: 'RUSSIA'),
      legal_bases: [Ammitto::Ontology::ValueObjects::LegalInstrument.new(identifier: 'O-27')],
      effects: [Ammitto::Ontology::ValueObjects::SanctionEffect.new(effect_type: 'asset_freeze')],
      period: Ammitto::Ontology::ValueObjects::TemporalPeriod.new(listed_date: Date.new(2022, 3, 1))
    )

    expect(entry.authority.name).to eq('SECO')
    expect(entry.effects.first).to be_asset_freeze
    expect(entry.period.active?).to be(true)
  end

  it 'round-trips the composed entry through YAML' do
    entry = described_class.new(
      id: 'entry/ch/1', status: 'active',
      effects: [Ammitto::Ontology::ValueObjects::SanctionEffect.new(effect_type: 'travel_ban')]
    )
    restored = described_class.from_yaml(entry.to_yaml)
    expect(restored.id).to eq('entry/ch/1')
    expect(restored.effects.first).to be_travel_ban
  end
end
