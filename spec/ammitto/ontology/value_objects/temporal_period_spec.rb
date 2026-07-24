# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::TemporalPeriod do
  let(:today) { Date.new(2026, 7, 23) }

  describe '#active?' do
    it 'is active with no dates at all' do
      expect(described_class.new.active?(as_of: today)).to be(true)
    end

    it 'is inactive before the effective date and after expiry' do
      period = described_class.new(effective_date: today + 1)
      expect(period.active?(as_of: today)).to be(false)

      period = described_class.new(expiry_date: today - 1)
      expect(period.active?(as_of: today)).to be(false)
    end

    it 'treats the expiry day itself as still active (exclusive comparison)' do
      period = described_class.new(expiry_date: today)
      expect(period.active?(as_of: today)).to be(true)
    end
  end

  describe '#expired?' do
    it 'is truthy only after the expiry date' do
      expect(described_class.new(expiry_date: today - 1).expired?(as_of: today)).to be(true)
      expect(described_class.new(expiry_date: today).expired?(as_of: today)).to be(false)
      expect(described_class.new.expired?(as_of: today)).to be_falsey
    end
  end

  describe '#duration_days' do
    it 'needs both effective and expiry dates' do
      period = described_class.new(effective_date: today, expiry_date: today + 30)
      expect(period.duration_days).to eq(30)
      expect(described_class.new(effective_date: today).duration_days).to be_nil
    end
  end

  it 'defaults is_indefinite to false and omits it from to_hash' do
    period = described_class.new(listed_date: Date.new(2022, 1, 1))
    expect(period.is_indefinite).to be(false)
    expect(period.to_hash).to eq({ listed_date: '2022-01-01' })
  end
end
