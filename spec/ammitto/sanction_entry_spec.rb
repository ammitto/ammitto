# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::SanctionEntry do
  let(:authority) { Ammitto::Authority.find('un') }
  let(:regime) { Ammitto::SanctionRegime.new(name: 'DPRK', code: 'DPRK') }
  let(:period) { Ammitto::TemporalPeriod.new(listed_date: '2020-01-01', is_indefinite: true) }

  let(:modification) do
    Ammitto::Ontology::Sanction::SanctionPeriodModification.new(
      id: 'https://www.ammitto.org/modification/cn/20250514-20257',
      target_type: 'announcement',
      target_announcement_id: 'https://www.ammitto.org/announcement/cn/20257',
      target_announcement_document_id: '〔2025〕7号',
      action: 'suspend',
      effective_date: Date.new(2025, 5, 14),
      until_date: Date.new(2025, 8, 12),
      notes: '暂停4月4日公告（不可靠实体清单工作机制〔2025〕7号）相关措施90天'
    )
  end

  let(:notice_reference) do
    Ammitto::NoticeReference.new(
      notice_number: '2025-05-14-22-00',
      notice_date: Date.new(2025, 5, 14),
      notice_title: '商务部新闻发言人就暂停措施答记者问'
    )
  end

  def change(date:, to_status:, end_date: nil, reason: modification.notes)
    Ammitto::StatusChange.new(
      date: date,
      from_status: 'active',
      to_status: to_status,
      suspension_end_date: end_date,
      reason: reason,
      notice_reference: notice_reference
    )
  end

  subject do
    described_class.new(
      id: 'https://ammitto.org/entry/un/test-1',
      entity_id: 'https://ammitto.org/entity/test-1',
      authority: authority,
      regime: regime,
      period: period,
      status: 'active',
      reference_number: 'TEST.001'
    )
  end

  it 'has correct status' do
    expect(subject.status).to eq('active')
  end

  it 'is active' do
    expect(subject.active?).to be true
  end

  it 'returns authority code' do
    expect(subject.authority_code).to eq('un')
  end

  it 'matches search term in reference number' do
    expect(subject.matches?('TEST')).to be true
    expect(subject.matches?('001')).to be true
  end

  it 'matches search term in regime' do
    expect(subject.matches?('DPRK')).to be true
  end

  it 'carries modifications and status changes through JSON round-trip' do
    entry = described_class.new(
      id: 'https://www.ammitto.org/entry/cn/unreliable-entity-list/20257-acme',
      status: 'suspended',
      modifications: [modification],
      status_history: [change(date: '2025-05-14', to_status: 'suspended', end_date: Date.new(2025, 8, 12))]
    )

    restored = described_class.from_json(entry.to_json)

    expect(restored.modifications.first.target_announcement_document_id).to eq('〔2025〕7号')
    expect(restored.status_history.first.to_status).to eq('suspended')
    expect(restored.status_history.first.suspension_end_date).to eq(Date.new(2025, 8, 12))
    expect(restored.status_history.first.notice_reference.notice_number).to eq('2025-05-14-22-00')
  end

  describe '#status_as_of' do
    it 'returns active before a stated suspension and after it ends' do
      entry = described_class.new(
        status: 'suspended',
        status_history: [change(
          date: '2025-05-14', to_status: 'suspended', end_date: Date.new(2025, 8, 12)
        )]
      )

      expect(entry.status_as_of(Date.new(2025, 5, 13))).to eq('active')
      expect(entry.status_as_of(Date.new(2025, 5, 14))).to eq('suspended')
      expect(entry.status_as_of(Date.new(2025, 8, 13))).to eq('active')
      expect(entry.status).to eq('suspended')
    end

    it 'is active before a first change that names no earlier status' do
      entry = described_class.new(
        status: 'suspended',
        status_history: [Ammitto::StatusChange.new(date: '2025-05-14', to_status: 'suspended')]
      )

      expect(entry.status_as_of(Date.new(2025, 5, 13))).to eq('active')
    end

    it 'answers the current status when there is no history' do
      expect(described_class.new(status: 'delisted').status_as_of(Date.new(2026, 1, 1))).to eq('delisted')
    end

    it 'keeps an open-ended suspension in force' do
      entry = described_class.new(
        status_history: [change(date: '2025-05-14', to_status: 'suspended')]
      )

      expect(entry.status_as_of(Date.new(2026, 10, 7))).to eq('suspended')
    end

    it 'makes termination final' do
      entry = described_class.new(
        status_history: [
          change(date: '2025-08-12', to_status: 'terminated', reason: '停止相关措施'),
          change(date: '2025-11-10', to_status: 'suspended')
        ],
        status: 'suspended'
      )

      expect(entry.status_as_of(Date.new(2026, 1, 1))).to eq('terminated')
    end
  end
end
