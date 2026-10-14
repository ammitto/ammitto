# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ch::SanctionedObject do
  describe '#imo_number' do
    it 'accepts the explicit IMO number label' do
      expect(described_class.new(other_information: 'IMO number: 9278064').imo_number).to eq('9278064')
    end

    it 'preserves the number under the observed SECO label typo' do
      expect(described_class.new(other_information: 'IMO Numbe: 9009085').imo_number).to eq('9009085')
    end

    it 'does not invent an IMO from unlabeled or overlong digits' do
      ['Reference 9278064', 'IMO number: 92780641', nil].each do |information|
        expect(described_class.new(other_information: information).imo_number).to be_nil
      end
    end
  end
end
