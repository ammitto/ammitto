# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu/sanction_entity'

# Named `_identifier_spec` rather than `sanction_entity_spec` because the
# birthdate-related behaviour of this class already has its own spec at
# spec/ammitto/sources/eu/birthdate_spec.rb.
RSpec.describe Ammitto::Sources::Eu::SanctionEntity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is eu_reference_number when present' do
      expect(described_class.new(eu_reference_number: 'EU.1234.99').identifier)
        .to eq('EU.1234.99')
    end

    it 'is nil when eu_reference_number is blank' do
      expect(described_class.new(eu_reference_number: nil).identifier).to be_nil
    end
  end
end
