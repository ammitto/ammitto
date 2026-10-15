# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::Sanction::StatusHistory do
  let(:attributes) do
    {
      from_status: 'active',
      to_status: 'suspended',
      date: Date.new(2025, 5, 14),
      timestamp: '2025-05-14T10:30:00+08:00',
      reason: 'Suspended by official notice',
      suspension_end_date: Date.new(2025, 8, 14),
      notice_reference: {
        notice_number: '2025-7',
        notice_date: Date.new(2025, 5, 14),
        notice_title: 'Suspension notice'
      }
    }
  end

  it 'accepts the legacy status name when no transition target is supplied' do
    history = described_class.new(status: 'delisted')

    expect(history.to_status).to eq('delisted')
    expect(history.to_hash[:to_status]).to eq('delisted')
  end

  it 'preserves an explicit transition target alongside the legacy status' do
    history = described_class.new(status: 'active', to_status: 'suspended')

    expect(history.status).to eq('active')
    expect(history.to_status).to eq('suspended')
    expect(history.to_hash[:to_status]).to eq('suspended')
  end

  %i[json yaml].each do |format|
    it "retains the dated transition and its notice through #{format} hydration" do
      history = described_class.new(attributes)
      hydrated = described_class.public_send("from_#{format}", history.public_send("to_#{format}"))

      expect(hydrated.to_hash).to eq(history.to_hash)
      expect(hydrated.date).to eq(Date.new(2025, 5, 14))
      expect(hydrated.timestamp).to eq('2025-05-14T10:30:00+08:00')
      expect(hydrated.suspension_end_date).to eq(Date.new(2025, 8, 14))
      expect(hydrated.notice_reference.notice_number).to eq('2025-7')
      expect(hydrated).to be_frozen
      expect(hydrated.notice_reference).to be_frozen
    end
  end

  it 'owns its reason and notice without freezing or retaining caller strings' do
    reason = +'Original reason'
    number = +'2025-7'
    history = described_class.new(reason: reason, notice_reference: { notice_number: number })
    reason.replace('Changed outside')
    number.replace('Changed outside')

    expect(history.reason).to eq('Original reason')
    expect(history.notice_reference.notice_number).to eq('2025-7')
    expect { history.reason << ' changed' }.to raise_error(FrozenError)
    expect { history.notice_reference.notice_number << ' changed' }.to raise_error(FrozenError)
  end

  it 'returns a sealed replacement while preserving the original transition' do
    history = described_class.new(attributes)
    replacement = history.with(to_status: 'delisted', reason: 'Final notice')

    expect(history.to_status).to eq('suspended')
    expect(history.reason).to eq('Suspended by official notice')
    expect(replacement.to_status).to eq('delisted')
    expect(replacement.reason).to eq('Final notice')
    expect(replacement.timestamp).to eq(history.timestamp)
    expect(replacement.notice_reference.to_hash).to eq(history.notice_reference.to_hash)
    expect(replacement).to be_frozen
    expect(replacement.notice_reference).to be_frozen
  end
end
