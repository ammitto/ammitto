# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Transformers::Registry do
  describe '.get' do
    it 'returns Uk::Transformer for :uk' do
      transformer = described_class.get(:uk)
      expect(transformer).to be_a(Ammitto::Sources::Uk::Transformer)
    end

    it 'returns Eu::Transformer for :eu' do
      transformer = described_class.get(:eu)
      expect(transformer).to be_a(Ammitto::Sources::Eu::Transformer)
    end

    it 'returns Un::Transformer for :un' do
      transformer = described_class.get(:un)
      expect(transformer).to be_a(Ammitto::Sources::Un::Transformer)
    end

    it 'returns Us::Transformer for :us' do
      transformer = described_class.get(:us)
      expect(transformer).to be_a(Ammitto::Sources::Us::Transformer)
    end

    it 'returns Wb::Transformer for :wb' do
      transformer = described_class.get(:wb)
      expect(transformer).to be_a(Ammitto::Sources::Wb::Transformer)
    end

    it 'returns Au::Transformer for :au' do
      transformer = described_class.get(:au)
      expect(transformer).to be_a(Ammitto::Sources::Au::Transformer)
    end

    it 'returns Ca::Transformer for :ca' do
      transformer = described_class.get(:ca)
      expect(transformer).to be_a(Ammitto::Sources::Ca::Transformer)
    end

    it 'returns Ch::Transformer for :ch' do
      transformer = described_class.get(:ch)
      expect(transformer).to be_a(Ammitto::Sources::Ch::Transformer)
    end

    it 'returns Cn::Transformer for :cn' do
      transformer = described_class.get(:cn)
      expect(transformer).to be_a(Ammitto::Sources::Cn::Transformer)
    end

    it 'returns Ru::Transformer for :ru' do
      transformer = described_class.get(:ru)
      expect(transformer).to be_a(Ammitto::Sources::Ru::Transformer)
    end

    it 'returns nil for unknown source' do
      expect(described_class.get(:unknown)).to be_nil
    end
  end

  describe '.supported_sources' do
    it 'returns array of supported source codes' do
      expect(described_class.supported_sources).to contain_exactly(
        :uk, :eu, :un, :us, :wb, :au, :ca, :ch, :cn, :ru
      )
    end
  end

  describe '.supported?' do
    it 'returns true for supported sources' do
      expect(described_class.supported?(:uk)).to be true
      expect(described_class.supported?(:eu)).to be true
    end

    it 'returns false for unsupported sources' do
      expect(described_class.supported?(:unknown)).to be false
    end
  end
end

RSpec.describe Ammitto::Transformers::BaseTransformer do
  let(:transformer) { described_class.new(:test) }

  describe '#source_code' do
    it 'returns the source code' do
      expect(transformer.source_code).to eq(:test)
    end
  end

  describe '#transform' do
    it 'raises NotImplementedError' do
      expect { transformer.transform({}) }.to raise_error(NotImplementedError)
    end
  end

  describe '#generate_entity_id' do
    it 'generates a proper entity URI' do
      id = transformer.send(:generate_entity_id, 'TEST123')
      expect(id).to eq('https://www.ammitto.org/entity/test/TEST123')
    end
  end

  describe '#generate_entry_id' do
    it 'generates a proper entry URI' do
      id = transformer.send(:generate_entry_id, 'TEST123')
      expect(id).to eq('https://www.ammitto.org/entry/test/TEST123')
    end
  end

  describe '#authority' do
    it 'returns the authority for the source' do
      auth = transformer.send(:authority)
      expect(auth).to be_nil # :test is not a registered authority
    end
  end
end

RSpec.describe Ammitto::Sources::Uk::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :uk' do
      expect(transformer.source_code).to eq(:uk)
    end
  end

  describe '#authority' do
    it 'returns UK authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('uk')
      expect(auth.name).to eq('United Kingdom (OFSI)')
    end
  end
end

RSpec.describe Ammitto::Sources::Eu::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :eu' do
      expect(transformer.source_code).to eq(:eu)
    end
  end

  describe '#authority' do
    it 'returns EU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('eu')
      expect(auth.name).to eq('European Union')
    end
  end
end

RSpec.describe Ammitto::Sources::Un::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :un' do
      expect(transformer.source_code).to eq(:un)
    end
  end

  describe '#authority' do
    it 'returns UN authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('un')
      expect(auth.name).to eq('United Nations')
    end
  end
end

RSpec.describe Ammitto::Sources::Us::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :us' do
      expect(transformer.source_code).to eq(:us)
    end
  end

  describe '#authority' do
    it 'returns US authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('us')
      expect(auth.name).to eq('United States (OFAC)')
    end
  end
end

RSpec.describe Ammitto::Sources::Wb::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :wb' do
      expect(transformer.source_code).to eq(:wb)
    end
  end

  describe '#authority' do
    it 'returns WB authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('wb')
      expect(auth.name).to eq('World Bank')
    end
  end
end

RSpec.describe Ammitto::Sources::Au::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :au' do
      expect(transformer.source_code).to eq(:au)
    end
  end

  describe '#authority' do
    it 'returns AU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('au')
      expect(auth.name).to eq('Australia (DFAT)')
    end
  end
end

RSpec.describe Ammitto::Sources::Ca::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ca' do
      expect(transformer.source_code).to eq(:ca)
    end
  end

  describe '#authority' do
    it 'returns CA authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ca')
      expect(auth.name).to eq('Canada (SEFO)')
    end
  end
end

RSpec.describe Ammitto::Sources::Ch::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ch' do
      expect(transformer.source_code).to eq(:ch)
    end
  end

  describe '#authority' do
    it 'returns CH authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ch')
      expect(auth.name).to eq('Switzerland (SECO)')
    end
  end
end

RSpec.describe Ammitto::Sources::Cn::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :cn' do
      expect(transformer.source_code).to eq(:cn)
    end
  end

  describe '#authority' do
    it 'returns CN authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('cn')
      expect(auth.name).to eq('China (MOFCOM/MFA)')
    end
  end
end

RSpec.describe Ammitto::Sources::Ru::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ru' do
      expect(transformer.source_code).to eq(:ru)
    end
  end

  describe '#authority' do
    it 'returns RU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ru')
      expect(auth.name).to eq('Russia (MID/CBR)')
    end
  end
end
