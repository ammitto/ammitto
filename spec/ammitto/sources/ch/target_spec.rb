# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ch::Target do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'prefers ssid when it is present' do
      target = described_class.new(ssid: 'SSID-42')

      expect(target.identifier).to eq('SSID-42')
    end

    it 'falls through to a slugged full_name when ssid is blank' do
      target = described_class.new(ssid: nil)
      allow(target).to receive(:full_name).and_return('Jean Paul Dupont')

      expect(target.identifier).to eq('Jean-Paul-Dupont')
    end

    # full_name&.gsub(/\s+/, '-') turns "" into "" rather than nil, so the
    # safe-navigation operator alone did not close this hole.
    it 'closes the hole where a gsub kept a blank string blank' do
      target = described_class.new(ssid: nil, individual: nil, entity: nil)

      expect(target.identifier).to be_nil
    end

    it 'treats whitespace-only ssid as absent, not as an identifier' do
      target = described_class.new(ssid: '   ', individual: nil, entity: nil)

      expect(target.identifier).to be_nil
    end
  end
end
