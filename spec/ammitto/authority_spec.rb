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

  describe '.code_from' do
    {
      'https://www.ammitto.org/authority/UN' => 'un',
      'https://www.ammitto.org/authority/un/' => 'un',
      'EU' => 'eu',
      { '@id' => 'https://www.ammitto.org/authority/uk' } => 'uk',
      { id: 'JP' } => 'jp',
      'https://example.org/authority/un' => nil,
      'ftp://www.ammitto.org/authority/un' => nil,
      'https://www.ammitto.org/entity/un/1' => nil,
      '  ' => nil,
      'eu_vessels' => 'eu_vessels',
      'has space' => nil,
      'a/b' => nil,
      '_x' => nil,
      ' un ' => nil,
      "un\n" => nil,
      "\u212Ae" => nil,
      'https://www.ammitto.org/authority/un?x=1' => nil,
      %w[un] => nil
    }.each do |value, code|
      it "reads #{value.inspect} as #{code.inspect}" do
        expect(described_class.code_from(value)).to eq(code)
      end
    end
  end
end
