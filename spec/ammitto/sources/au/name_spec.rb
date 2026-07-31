# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Name do
  describe '#primary?' do
    it 'returns true for Primary Name' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::PRIMARY,
        script: 'Latn'
      )
      expect(name.primary?).to be true
    end

    it 'returns false for Alias' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::ALIAS,
        script: 'Latn'
      )
      expect(name.primary?).to be false
    end
  end

  describe '#original_script?' do
    it 'returns true for Original Script' do
      name = described_class.new(
        text: 'محمد',
        name_type: Ammitto::Sources::Au::NameType::ORIGINAL_SCRIPT,
        script: 'Arab'
      )
      expect(name.original_script?).to be true
    end
  end

  describe '#strong_alias?' do
    it 'returns true for strong alias' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::ALIAS,
        script: 'Latn',
        alias_strength: Ammitto::Sources::Au::AliasStrength::STRONG
      )
      expect(name.strong_alias?).to be true
    end
  end
end
