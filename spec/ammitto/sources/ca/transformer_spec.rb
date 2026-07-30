# frozen_string_literal: true

require 'spec_helper'

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
