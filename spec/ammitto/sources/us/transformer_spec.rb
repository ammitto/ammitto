# frozen_string_literal: true

require 'spec_helper'

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
