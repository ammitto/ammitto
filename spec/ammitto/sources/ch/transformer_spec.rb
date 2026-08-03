# frozen_string_literal: true

require 'spec_helper'

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
