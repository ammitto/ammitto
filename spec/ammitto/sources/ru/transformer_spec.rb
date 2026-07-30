# frozen_string_literal: true

require 'spec_helper'

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
