# frozen_string_literal: true

require 'spec_helper'

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
