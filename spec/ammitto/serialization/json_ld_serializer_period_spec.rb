# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/serialization/json_ld_serializer'

RSpec.describe Ammitto::Serialization::JsonLdSerializer do
  subject(:serializer) { described_class.new }

  def serialized_period(value)
    entry = Ammitto::SanctionEntry.new(period: Ammitto::TemporalPeriod.new(last_updated: value))
    serializer.serialize_entry(entry).fetch('period')
  end

  [nil, '', "\n      ", "\t\r\n", "\u2003"].each do |value|
    it "omits absent lastUpdated #{value.inspect}" do
      expect(serialized_period(value)).not_to have_key('lastUpdated')
    end
  end

  ['1964', '1964-02', '1964-02-29', '2026-10-14T10:00:00Z', ' 1964-02 '].each do |value|
    it "preserves meaningful lastUpdated #{value.inspect} exactly" do
      expect(serialized_period(value)['lastUpdated']).to eq(value)
    end
  end
end
