# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/ru/sanctioned_entity'

RSpec.describe Ammitto::Sources::Ru::SanctionedEntity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'prefers english_name when present' do
      entity = described_class.new(english_name: 'Ivan Ivanov', russian_name: 'Иван Иванов')

      expect(entity.identifier).to eq('Ivan Ivanov')
    end

    it 'falls through to russian_name when english_name is blank' do
      entity = described_class.new(english_name: nil, russian_name: 'Иван Иванов')

      expect(entity.identifier).to eq('Иван Иванов')
    end

    it 'is nil when neither candidate carries anything usable' do
      entity = described_class.new(english_name: nil, russian_name: nil)

      expect(entity.identifier).to be_nil
    end
  end
end
