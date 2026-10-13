# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/uk/designation'

RSpec.describe Ammitto::Sources::Uk::Designation do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is unique_id when present' do
      expect(described_class.new(unique_id: 'GBR-0123').identifier)
        .to eq('GBR-0123')
    end

    it 'is nil when unique_id is blank' do
      expect(described_class.new(unique_id: nil).identifier).to be_nil
    end

    it 'treats whitespace as absent, not as an identifier' do
      expect(described_class.new(unique_id: '   ').identifier).to be_nil
    end
  end

  describe 'detail blocks' do
    it 'keeps the titles of an individual' do
      expect(UkExcerpt.designation('AFG0006').titles).to eq(%w[Mullah Haji])
    end

    it 'keeps the ship details' do
      ship = UkExcerpt.designation('DPR0075').ship_details.ship

      expect(ship.imo_numbers).to eq(['IMO9562233'])
      expect(ship.current_owner_operators).to eq(['Global United Shipping India'])
      expect(ship.current_believed_flags).to eq(['Comoros'])
      expect(ship.types_of_ship).to eq(['Bulk Carrier'])
      expect(ship.tonnages).to eq(['7078'])
      expect(ship.years_built).to eq(['2011'])
    end

    it 'keeps the entity details and contact lists' do
      designation = UkExcerpt.designation('BEL0164')

      expect(designation.entity_details.business_registration_numbers)
        .to eq(['Belarusian tax number: 400085002'])
      expect(designation.phone_numbers).to eq(['+375232509720'])
      expect(designation.websites).to eq(['https://stankogomel.by/'])
      expect(designation.email_addresses).to eq(['Stankogomel@stankogomel.by'])
    end
  end
end
