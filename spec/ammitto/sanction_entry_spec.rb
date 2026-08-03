# frozen_string_literal: true

RSpec.describe Ammitto::SanctionEntry do
  let(:authority) { Ammitto::Authority.find('un') }
  let(:regime) { Ammitto::SanctionRegime.new(name: 'DPRK', code: 'DPRK') }
  let(:period) { Ammitto::TemporalPeriod.new(listed_date: '2020-01-01', is_indefinite: true) }

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

  describe 'status changes' do
    it 'can add status change to history' do
      change = Ammitto::StatusChange.new(
        date: Time.now,
        from_status: 'active',
        to_status: 'suspended',
        reason: 'Test suspension'
      )

      subject.add_status_change(change)

      expect(subject.status_history.size).to eq(1)
      expect(subject.status).to eq('suspended')
      expect(subject.suspended?).to be true
    end
  end
end
