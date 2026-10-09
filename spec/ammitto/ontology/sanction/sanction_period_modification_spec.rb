# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/sanction/sanction_period_modification'
require 'ammitto/sources/cn/measure_modification'
require 'ammitto/sources/cn/transformer'

RSpec.describe Ammitto::Ontology::Sanction::SanctionPeriodModification do
  let(:target_entry_ids) do
    [
      'https://www.ammitto.org/entry/cn/unreliable-entity-list/20257-acme',
      'https://www.ammitto.org/entry/cn/unreliable-entity-list/20257-beta'
    ]
  end

  let(:notice) do
    {
      'id' => 'https://www.ammitto.org/announcement/cn/202511051700',
      'document_id' => '2025-11-05-17-00',
      'publish_date' => '2025-11-05',
      'title' => '商务部新闻发言人就调整不可靠实体清单措施答记者问'
    }
  end

  let(:legal_citation) do
    Ammitto::Ontology::ValueObjects::LegalCitation.new(
      legal_instrument_id: 'cn/mofcom-unreliable-entity-list-provisions',
      articles: ['第一条']
    )
  end

  let(:modification) do
    described_class.new(
      id: 'https://www.ammitto.org/modification/cn/202511051700-20257',
      target_type: 'announcement',
      target_id: target_entry_ids,
      target_announcement_id: 'https://www.ammitto.org/announcement/cn/20257',
      target_announcement_document_id: '〔2025〕7号',
      target_announcement_date: Date.new(2025, 4, 4),
      action: 'suspend',
      effective_date: Date.new(2025, 11, 10),
      until_date: Date.new(2026, 11, 10),
      announcement: notice,
      affected_entity_count: 2,
      legal_citations: [legal_citation],
      notes: '继续暂停4月4日公告（不可靠实体清单工作机制公告〔2025〕7号）相关措施1年'
    )
  end

  describe '#suspension?' do
    it 'returns true when action is suspend' do
      expect(described_class.new(action: 'suspend')).to be_suspension
    end

    it 'returns false for other actions' do
      expect(described_class.new(action: 'stop')).not_to be_suspension
    end
  end

  describe '#delisting?' do
    it 'returns true when action is stop' do
      expect(described_class.new(action: 'stop')).to be_delisting
    end

    it 'returns false for other actions' do
      expect(described_class.new(action: 'suspend')).not_to be_delisting
    end
  end

  describe '#effective_datetime' do
    it 'uses the effective date and supplied time' do
      mod = described_class.new(effective_date: Date.new(2025, 1, 1), effective_time: '08:30')
      expect(mod.effective_datetime).to eq('2025-01-01T08:30:00')
    end

    it 'defaults to midnight' do
      mod = described_class.new(effective_date: Date.new(2025, 1, 1))
      expect(mod.effective_datetime).to eq('2025-01-01T00:00:00')
    end

    it 'returns nil without a date' do
      expect(described_class.new(effective_time: '08:30').effective_datetime).to be_nil
    end
  end

  describe '#until_datetime' do
    it 'uses the end date and supplied time' do
      mod = described_class.new(until_date: Date.new(2025, 4, 1), until_time: '18:00')
      expect(mod.until_datetime).to eq('2025-04-01T18:00:00')
    end

    it 'defaults to the end of the day' do
      mod = described_class.new(until_date: Date.new(2025, 4, 1))
      expect(mod.until_datetime).to eq('2025-04-01T23:59:00')
    end

    it 'returns nil without an end date' do
      expect(described_class.new.until_datetime).to be_nil
    end
  end

  describe '#batch?' do
    it 'returns true for multiple affected entities' do
      expect(described_class.new(affected_entity_count: 2)).to be_batch
    end

    it 'returns false for one or no affected entities' do
      expect(described_class.new(affected_entity_count: 1)).not_to be_batch
      expect(described_class.new).not_to be_batch
    end
  end

  it 'stores legal citations' do
    citation = Ammitto::Ontology::ValueObjects::LegalCitation.new(
      legal_instrument_id: 'cn/mofcom-unreliable-entity-list-provisions',
      articles: ['第一条']
    )

    expect(described_class.new(legal_citations: [citation]).legal_citations).to eq([citation])
  end

  it 'does not expose a status or parsed duration on a modification node' do
    expect(modification).not_to respond_to(:status)
    expect(modification).not_to respond_to(:duration_days)
    expect(modification.notes).to include('1年')
  end

  it 'serializes and round-trips the publication fields' do
    restored = described_class.from_json(modification.to_json)

    expect(restored.target_type).to eq('announcement')
    expect(restored.target_id).to eq(target_entry_ids)
    expect(restored.target_announcement_id).to eq(
      'https://www.ammitto.org/announcement/cn/20257'
    )
    expect(restored.target_announcement_document_id).to eq('〔2025〕7号')
    expect(restored.target_announcement_date).to eq(Date.new(2025, 4, 4))
    expect(restored.effective_date).to eq(Date.new(2025, 11, 10))
    expect(restored.until_date).to eq(Date.new(2026, 11, 10))
    expect(restored.announcement).to eq(notice)
    expect(restored.legal_citations.first.legal_instrument_id).to eq(
      'cn/mofcom-unreliable-entity-list-provisions'
    )
    expect(restored.notes).to eq(modification.notes)
    expect(restored).not_to respond_to(:status)
  end

  it 'transforms the real 2025 source shape into a minted target IRI' do
    source = Ammitto::Sources::Cn::MeasureModification.from_hash(
      'announcement' => {
        'document_id' => '2025-05-14-22-00',
        'publish_date' => '2025-05-14',
        'title' => [{ 'zh-Hans' => '商务部新闻发言人就暂停措施答记者问' }],
        'url' => 'https://www.mofcom.gov.cn/example',
        'authority' => 'cn/ministry-of-commerce',
        'content' => '暂停相关措施。'
      },
      'measure_modifications' => {
        'instruments' => [],
        'modifications' => [{
          'action' => 'suspend',
          'target_announcement_id' => '〔2025〕7号',
          'target_announcement_date' => '2025-04-04',
          'effective_date' => '2025-05-14',
          'until_date' => '2025-08-12',
          'notes' => '暂停4月4日公告（不可靠实体清单工作机制〔2025〕7号）相关措施90天'
        }]
      }
    )
    result = Ammitto::Sources::Cn::Transformer.new.transform_modification(source)
    transformed = result[:modifications].first

    expect(transformed.target_announcement_id).to eq(
      'https://www.ammitto.org/announcement/cn/20257'
    )
    expect(transformed.target_announcement_document_id).to eq('〔2025〕7号')
    expect(transformed.notes).to eq(source.modifications.first.notes)
    expect(transformed.announcement['id']).to eq(result[:official_announcement].id)
    expect(transformed).not_to respond_to(:status)
  end
end
