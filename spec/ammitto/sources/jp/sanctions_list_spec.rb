# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/jp'

RSpec.describe Ammitto::Sources::Jp::SanctionsList do
  describe '.from_pdf' do
    it 'refuses instead of succeeding with zero entities' do
      expect { described_class.from_pdf('end-user-list.pdf') }
        .to raise_error(NotImplementedError, /cannot parse PDFs/)
    end
  end

  describe '.from_converted_data' do
    it 'builds a list from already-converted structured data' do
      list = described_class.from_converted_data(
        'entities' => [
          { 'id' => 'meti-1', 'name' => 'Example Institute' }
        ]
      )

      expect(list.source).to eq('jp')
      expect(list.count).to eq(1)
      expect(list.all_entities.first.name).to eq('Example Institute')
    end

    it 'builds an empty list when no entities are given' do
      list = described_class.from_converted_data({})

      expect(list.count).to eq(0)
    end
  end
end
