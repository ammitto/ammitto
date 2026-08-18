# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/serialization/turtle_exporter'

# The published all.ttl did not parse. Values were emitted as IRIs on
# shape alone — anything starting with http(s) — and free text can begin
# with a URL: Australian remarks open with the company's website and
# continue in prose. Those became IRIREFs containing spaces, which the
# Turtle grammar forbids, and RDF::Graph.load died at the first one
# rather than skipping it.
#
# There was no spec for this class at all before.
RSpec.describe Ammitto::Serialization::TurtleExporter do
  # The constructor takes paths it never reads for this conversion.
  subject(:exporter) { described_class.new(File::NULL, File::NULL) }

  def convert(value)
    exporter.send(:convert_value, value)
  end

  it 'emits a bare URL as an IRI' do
    expect(convert('https://example.test/a')).to eq(['<https://example.test/a>'])
  end

  it 'emits prose beginning with a URL as a literal' do
    # Shortened from a real au record.
    text = 'https://enics.aero/; Listing: Autonomous Sanctions Amendment (No. 1) Instrument 2024'

    result = convert(text).first

    expect(result).not_to start_with('<')
    expect(result).to include('enics.aero')
  end

  it 'never emits an IRIREF containing a character the grammar forbids' do
    [
      'https://example.test/a b',
      "https://example.test/a\tb",
      # The grammar forbids every codepoint in #x00-#x20 and Ruby's \s
      # covers six of them, so the controls it misses are named here.
      "https://example.test/a\x00b",
      "https://example.test/a\x08b",
      "https://example.test/a\x0Eb",
      "https://example.test/a\x1Fb",
      'https://example.test/a<b',
      'https://example.test/a"b',
      'https://ipnrf.ru/ ; Company Identification No., 1177456104638'
    ].each do |value|
      result = convert(value).first
      next unless result.start_with?('<')

      expect(result).not_to match(/[\x00-\x20<>"{}|^`\\]/),
                            "#{value.inspect} -> #{result.inspect}"
    end
  end

  it 'still emits an IRI carrying a character an IRIREF may hold' do
    # The guard must not reach past the grammar. Non-ASCII is legal in an
    # IRIREF, so widening to the control range must not demote it.
    value = 'https://example.test/café'

    expect(convert(value)).to eq(["<#{value}>"])
  end

  it 'still types dates and leaves other text alone' do
    expect(convert('2024-01-31')).to eq(['"2024-01-31"^^xsd:date'])
    expect(convert('plain').first).not_to start_with('<')
  end
end
