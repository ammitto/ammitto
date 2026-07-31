# frozen_string_literal: true

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
