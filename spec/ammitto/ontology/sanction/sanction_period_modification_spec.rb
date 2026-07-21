# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/sanction/sanction_period_modification'

RSpec.describe Ammitto::Ontology::Sanction::SanctionPeriodModification do
  describe '#initialize' do
    it 'creates a modification with all attributes' do
      mod = described_class.new(
        id: 'https://www.ammitto.org/modification/cn/2025-001',
        target_type: 'entry',
        target_id: 'https://www.ammitto.org/entry/cn/uel-2024-015',
        target_announcement_id: 'https://www.ammitto.org/announcement/cn/2024-015',
        target_announcement_date: Date.new(2024, 12, 15),
        affected_entity_count: 11,
        affected_entity_names: ['Entity A', 'Entity B'],
        action: 'suspend',
        effective_date: Date.new(2025, 1, 1),
        effective_time: '00:00',
        until_date: Date.new(2025, 4, 1),
        until_time: '23:59',
        duration_days: 90,
        duration_description: '90天',
        announcement_id: 'https://www.ammitto.org/announcement/cn/2025-001',
        status: 'active'
      )

      expect(mod.id).to eq('https://www.ammitto.org/modification/cn/2025-001')
      expect(mod.target_type).to eq('entry')
      expect(mod.target_id).to eq('https://www.ammitto.org/entry/cn/uel-2024-015')
      expect(mod.action).to eq('suspend')
      expect(mod.effective_date).to eq(Date.new(2025, 1, 1))
      expect(mod.until_date).to eq(Date.new(2025, 4, 1))
      expect(mod.duration_days).to eq(90)
      expect(mod.duration_description).to eq('90天')
      expect(mod.status).to eq('active')
    end

    it 'defaults status to active' do
      mod = described_class.new(action: 'suspend')
      expect(mod.status).to eq('active')
    end
  end

  describe '#suspension?' do
    it 'returns true when action is suspend' do
      mod = described_class.new(action: 'suspend')
      expect(mod.suspension?).to be true
    end

    it 'returns false for other actions' do
      mod = described_class.new(action: 'stop')
      expect(mod.suspension?).to be false
    end
  end

  describe '#delisting?' do
    it 'returns true when action is stop' do
      mod = described_class.new(action: 'stop')
      expect(mod.delisting?).to be true
    end

    it 'returns false for other actions' do
      mod = described_class.new(action: 'suspend')
      expect(mod.delisting?).to be false
    end
  end

  describe '#active?' do
    it 'returns true when status is active' do
      mod = described_class.new(status: 'active')
      expect(mod.active?).to be true
    end

    it 'returns false for other statuses' do
      mod = described_class.new(status: 'expired')
      expect(mod.active?).to be false
    end
  end

  describe '#expired?' do
    it 'returns true when suspension until_date is in the past' do
      mod = described_class.new(
        action: 'suspend',
        until_date: Date.today - 1
      )
      expect(mod.expired?).to be true
    end

    it 'returns false when suspension until_date is in the future' do
      mod = described_class.new(
        action: 'suspend',
        until_date: Date.today + 30
      )
      expect(mod.expired?).to be false
    end

    it 'returns false when action is not suspend' do
      mod = described_class.new(
        action: 'stop',
        until_date: Date.today - 1
      )
      expect(mod.expired?).to be false
    end

    it 'returns false when until_date is nil' do
      mod = described_class.new(action: 'suspend')
      expect(mod.expired?).to be false
    end
  end

  describe '#effective_datetime' do
    it 'returns ISO 8601 datetime string when date is present' do
      mod = described_class.new(
        effective_date: Date.new(2025, 1, 1),
        effective_time: '08:30'
      )
      expect(mod.effective_datetime).to eq('2025-01-01T08:30:00')
    end

    it 'uses 00:00 as default time' do
      mod = described_class.new(effective_date: Date.new(2025, 1, 1))
      expect(mod.effective_datetime).to eq('2025-01-01T00:00:00')
    end

    it 'returns nil when date is nil' do
      mod = described_class.new(effective_time: '08:30')
      expect(mod.effective_datetime).to be_nil
    end
  end

  describe '#until_datetime' do
    it 'returns ISO 8601 datetime string when date is present' do
      mod = described_class.new(
        until_date: Date.new(2025, 4, 1),
        until_time: '18:00'
      )
      expect(mod.until_datetime).to eq('2025-04-01T18:00:00')
    end

    it 'uses 23:59 as default time' do
      mod = described_class.new(until_date: Date.new(2025, 4, 1))
      expect(mod.until_datetime).to eq('2025-04-01T23:59:00')
    end

    it 'returns nil when date is nil' do
      mod = described_class.new
      expect(mod.until_datetime).to be_nil
    end
  end

  describe '#batch?' do
    it 'returns true when affected_entity_count > 1' do
      mod = described_class.new(affected_entity_count: 5)
      expect(mod.batch?).to be true
    end

    it 'returns false when affected_entity_count is 1' do
      mod = described_class.new(affected_entity_count: 1)
      expect(mod.batch?).to be false
    end

    it 'returns false when affected_entity_count is nil' do
      mod = described_class.new
      expect(mod.batch?).to be false
    end
  end

  describe 'with legal citations' do
    it 'stores legal citations' do
      citation = Ammitto::Ontology::ValueObjects::LegalCitation.new(
        legal_instrument_id: 'test-law',
        articles: ['第一条']
      )
      mod = described_class.new(legal_citations: [citation])
      expect(mod.legal_citations).to eq([citation])
    end
  end

  describe 'with multilingual reasons' do
    it 'stores localized reasons' do
      reason = Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: '测试原因',
        language: 'zh'
      )
      mod = described_class.new(reason: [reason])
      expect(mod.reason).to eq([reason])
    end
  end

  describe 'serialization' do
    let(:modification) do
      described_class.new(
        id: 'https://www.ammitto.org/modification/cn/2025-001',
        target_type: 'entry',
        target_id: 'https://www.ammitto.org/entry/cn/uel-2024-015',
        action: 'suspend',
        effective_date: Date.new(2025, 1, 1),
        until_date: Date.new(2025, 4, 1),
        duration_days: 90,
        status: 'active'
      )
    end

    it 'serializes to JSON' do
      json = modification.to_json
      parsed = JSON.parse(json)

      expect(parsed['id']).to eq('https://www.ammitto.org/modification/cn/2025-001')
      expect(parsed['target_type']).to eq('entry')
      expect(parsed['action']).to eq('suspend')
      expect(parsed['effective_date']).to eq('2025-01-01')
      expect(parsed['until_date']).to eq('2025-04-01')
      expect(parsed['duration_days']).to eq(90)
      expect(parsed['status']).to eq('active')
    end

    it 'deserializes from JSON' do
      json = '{"id":"test","action":"suspend","duration_days":90,"status":"active"}'
      result = described_class.from_json(json)

      expect(result.id).to eq('test')
      expect(result.action).to eq('suspend')
      expect(result.duration_days).to eq(90)
      expect(result.status).to eq('active')
    end
  end
end
