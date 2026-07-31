# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Sanction do
  describe '#effects' do
    it 'returns empty array when all flags are false' do
      sanction = described_class.new(
        targeted_financial_sanction: false,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to eq([])
    end

    it 'returns targeted_financial_sanction when TFS is true' do
      sanction = described_class.new(
        targeted_financial_sanction: true,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to eq(['targeted_financial_sanction'])
    end

    it 'returns multiple effects when multiple flags are true' do
      sanction = described_class.new(
        targeted_financial_sanction: true,
        travel_ban: true,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to contain_exactly('targeted_financial_sanction', 'travel_ban')
    end

    it 'returns maritime_restriction when set' do
      sanction = described_class.new(
        targeted_financial_sanction: false,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: true
      )
      expect(sanction.effects).to eq(['maritime_restriction'])
    end
  end

  describe '#regime_type' do
    it 'returns :autonomous for autonomous sanctions' do
      sanction = described_class.new(committees: 'Autonomous (Iran)')
      expect(sanction.regime_type).to eq(:autonomous)
    end

    it 'returns :un_security_council for UNSC sanctions' do
      sanction = described_class.new(committees: '1737 (Iran)')
      expect(sanction.regime_type).to eq(:un_security_council)
    end

    it 'returns nil when committees is nil' do
      sanction = described_class.new(committees: nil)
      expect(sanction.regime_type).to be_nil
    end
  end
end
