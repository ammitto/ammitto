# frozen_string_literal: true

require 'spec_helper'

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
