# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/jp/entity'

RSpec.describe Ammitto::Sources::Jp::Entity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. No naming collision with the real +id+ Lutaml attribute
  # this class defines: the new method is +#identifier+, not +#id+.
  describe '#identifier' do
    it 'is the raw id when present' do
      entity = described_class.new(id: 'JP1')

      expect(entity.identifier).to eq('JP1')
    end

    # The raw id wins even when it is punctuation-only text a downstream
    # layer cannot sanitize into anything ("!!!"): presence is about
    # whether the field carries text at all, not whether that text is
    # usable further downstream — the same distinction filename_from_ref
    # always drew from identifier selection.
    it 'is the raw id even when unique_identifier would be nil' do
      entity = described_class.new(id: '!!!')

      expect(entity.unique_identifier).to be_nil
      expect(entity.identifier).to eq('!!!')
    end

    # unique_identifier derives from id ("JP-#{id}", or nil when id has
    # no sanitizable content), so it is also nil whenever id is blank:
    # the second candidate can never actually rescue this one in
    # practice, but is kept for parity with the class it was copied from.
    it 'is nil when id is entirely blank' do
      entity = described_class.new(id: nil, name: 'Example')

      expect(entity.identifier).to be_nil
      expect(entity.unique_identifier).to be_nil
    end
  end
end
