# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/utils/iri_sanitizer'

# A Turtle IRIREF cannot contain a space. Regime codes reach the graph
# straight from the source, and Canada publishes bilingual ones with
# slashes, accents and spaces, so interpolating a code into an IRI
# produced 17 distinct identifiers that no RDF parser will read.
RSpec.describe Ammitto::Utils::IriSanitizer do
  describe '.regime_iri' do
    it 'mints a usable IRI from a bilingual code carrying spaces' do
      iri = described_class.regime_iri('CA_Belarus / Bélarus')

      expect(iri).not_to include(' ')
      expect(iri).to start_with('https://www.ammitto.org/regime/')
    end

    it 'never emits a character a Turtle IRIREF forbids' do
      codes = [
        'CAATSA - Russia',
        'CA_Extremist Settler Violence / Violence extrémiste des colons',
        'CA_Justice for Victims of Corrupt Foreign Officials Regulations (JVCFOR)',
        'SOUTH SUDAN'
      ]

      codes.each do |code|
        iri = described_class.regime_iri(code)
        # The delimiters the grammar excludes outright.
        expect(iri).not_to match(/[\s<>"{}|^`\\]/), "#{code.inspect} -> #{iri.inspect}"
      end
    end

    it 'keeps distinct codes distinct' do
      a = described_class.regime_iri('CAATSA - Russia')
      b = described_class.regime_iri('CAATSA - Iran')

      expect(a).not_to eq(b)
    end
  end

  describe 'idempotence' do
    # An IRI is rebuilt from a stored slug in several places, so a slug
    # that changes on a second pass advertises an @id that no node file
    # answers to. Truncation is what broke it: it cuts mid-word and
    # leaves the preceding hyphen at the end.
    long = 'CA_Justice for victims of corrupt foreign officials ' \
           'regulations (JVCFOR) / Reglement relatif a la justice'

    it 'sanitizes a truncated slug to itself' do
      once = described_class.sanitize(long)

      expect(described_class.sanitize(once)).to eq(once)
    end

    it 'leaves no trailing hyphen after truncating' do
      expect(described_class.sanitize(long)).not_to end_with('-')
    end

    it 'mints the same regime IRI from a code and from its own slug' do
      iri = described_class.regime_iri(long)
      slug = iri.split('/').last

      expect(described_class.regime_iri(slug)).to eq(iri)
    end
  end
end
