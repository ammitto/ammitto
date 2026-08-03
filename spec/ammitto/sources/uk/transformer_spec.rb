# frozen_string_literal: true

require 'spec_helper'

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
