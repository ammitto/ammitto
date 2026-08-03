# frozen_string_literal: true

require 'spec_helper'

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
