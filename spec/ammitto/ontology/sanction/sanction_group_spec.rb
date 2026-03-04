# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/sanction/sanction_group'

RSpec.describe Ammitto::Ontology::Sanction::SanctionGroup do
  describe '#initialize' do
    it 'creates a sanction group with all attributes' do
      group = described_class.new(
        id: 'https://www.ammitto.org/group/cn/2025-01-02-uel',
        announcement_id: 'https://www.ammitto.org/announcement/cn/2025-01-02',
        list_id: 'https://www.ammitto.org/list/cn/UEL',
        entry_ids: [
          'https://www.ammitto.org/entry/cn/uel-2025-001',
          'https://www.ammitto.org/entry/cn/uel-2025-002'
        ],
        entity_count: 2,
        effective_date: Date.new(2025, 1, 2),
        effective_time: '00:00',
        notes: 'Collective sanction'
      )

      expect(group.id).to eq('https://www.ammitto.org/group/cn/2025-01-02-uel')
      expect(group.announcement_id).to eq('https://www.ammitto.org/announcement/cn/2025-01-02')
      expect(group.list_id).to eq('https://www.ammitto.org/list/cn/UEL')
      expect(group.entry_ids).to eq([
                                      'https://www.ammitto.org/entry/cn/uel-2025-001',
                                      'https://www.ammitto.org/entry/cn/uel-2025-002'
                                    ])
      expect(group.entity_count).to eq(2)
      expect(group.effective_date).to eq(Date.new(2025, 1, 2))
      expect(group.effective_time).to eq('00:00')
      expect(group.notes).to eq('Collective sanction')
    end
  end

  describe '#shared_measures?' do
    it 'returns true when shared_measures is not empty' do
      effect = Ammitto::Ontology::ValueObjects::SanctionEffect.new(
        effect_type: 'asset_freeze',
        scope: 'full'
      )
      group = described_class.new(shared_measures: [effect])
      expect(group.shared_measures?).to be true
    end

    it 'returns false when shared_measures is empty' do
      group = described_class.new(shared_measures: [])
      expect(group.shared_measures?).to be false
    end

    it 'returns false when shared_measures is nil' do
      group = described_class.new
      expect(group.shared_measures?).to be false
    end
  end

  describe '#shared_reasons?' do
    it 'returns true when shared_reasons is not empty' do
      reason = Ammitto::Ontology::Sanction::SanctionReason.new(
        description: 'Test reason'
      )
      group = described_class.new(shared_reasons: [reason])
      expect(group.shared_reasons?).to be true
    end

    it 'returns false when shared_reasons is empty' do
      group = described_class.new(shared_reasons: [])
      expect(group.shared_reasons?).to be false
    end
  end

  describe '#effective_datetime' do
    it 'returns ISO 8601 datetime string when date is present' do
      group = described_class.new(
        effective_date: Date.new(2025, 1, 2),
        effective_time: '08:30'
      )
      expect(group.effective_datetime).to eq('2025-01-02T08:30:00')
    end

    it 'uses 00:00 as default time' do
      group = described_class.new(effective_date: Date.new(2025, 1, 2))
      expect(group.effective_datetime).to eq('2025-01-02T00:00:00')
    end

    it 'returns nil when date is nil' do
      group = described_class.new(effective_time: '08:30')
      expect(group.effective_datetime).to be_nil
    end
  end

  describe 'serialization' do
    let(:group) do
      described_class.new(
        id: 'https://www.ammitto.org/group/cn/2025-01-02-uel',
        announcement_id: 'https://www.ammitto.org/announcement/cn/2025-01-02',
        list_id: 'https://www.ammitto.org/list/cn/UEL',
        entry_ids: %w[entry-1 entry-2],
        entity_count: 2,
        effective_date: Date.new(2025, 1, 2)
      )
    end

    it 'serializes to JSON' do
      json = group.to_json
      parsed = JSON.parse(json)

      expect(parsed['id']).to eq('https://www.ammitto.org/group/cn/2025-01-02-uel')
      expect(parsed['announcement_id']).to eq('https://www.ammitto.org/announcement/cn/2025-01-02')
      expect(parsed['list_id']).to eq('https://www.ammitto.org/list/cn/UEL')
      expect(parsed['entry_ids']).to eq(%w[entry-1 entry-2])
      expect(parsed['entity_count']).to eq(2)
      expect(parsed['effective_date']).to eq('2025-01-02')
    end

    it 'deserializes from JSON' do
      json = '{"id":"test","entry_ids":["e1","e2"],"entity_count":2}'
      result = described_class.from_json(json)

      expect(result.id).to eq('test')
      expect(result.entry_ids).to eq(%w[e1 e2])
      expect(result.entity_count).to eq(2)
    end
  end
end
