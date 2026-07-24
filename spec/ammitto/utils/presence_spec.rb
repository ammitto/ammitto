# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Utils::Presence do
  describe '.blank?' do
    it 'is true for nil, false, empties, and whitespace-only strings' do
      [nil, false, '', '  ', ' ', [], {}].each do |value|
        expect(described_class.blank?(value)).to be(true), value.inspect
      end
    end

    it 'is false for anything carrying a value' do
      [0, 'x', ' x ', true, [1], { a: 1 }, Date.new(2026, 1, 1)].each do |value|
        expect(described_class.blank?(value)).to be(false), value.inspect
      end
    end
  end

  describe '.present?' do
    it 'inverts .blank?' do
      expect(described_class.present?('x')).to be(true)
      expect(described_class.present?(nil)).to be(false)
    end
  end
end
