# frozen_string_literal: true

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
      expect(authorities.size).to eq(16)
    end

    it 'covers every source the gem advertises' do
      require 'ammitto/config/defaults'
      missing = Ammitto::Config::Defaults::ALL_SOURCES.reject do |code|
        described_class.find(code.to_s)
      end
      expect(missing).to be_empty
    end
  end
end
