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

RSpec.describe Ammitto::Authority do
  describe '.find' do
    it 'returns authority for known code' do
      auth = described_class.find('eu')
      expect(auth).not_to be_nil
      expect(auth.id).to eq('eu')
      expect(auth.name).to eq('European Union')
    end

    it 'returns nil for unknown code' do
      expect(described_class.find('xyz')).to be_nil
    end
  end

  describe '.all' do
    it 'returns all registered authorities' do
      authorities = described_class.all
      expect(authorities).to be_an(Array)
      expect(authorities.size).to eq(10)
    end
  end
end

RSpec.describe Ammitto::TemporalPeriod do
  it 'is active when no expiry date' do
    period = described_class.new(listed_date: '2020-01-01', is_indefinite: true)
    expect(period.active?).to be true
  end

  it 'is not active when expiry date passed' do
    period = described_class.new(
      listed_date: '2020-01-01',
      expiry_date: '2020-12-31'
    )
    expect(period.active?).to be false
  end

  it 'calculates days until expiry' do
    future_date = Date.today + 30
    period = described_class.new(listed_date: '2020-01-01', expiry_date: future_date)
    expect(period.days_until_expiry).to be_within(1).of(30)
  end
end
