# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/tr/sanctions_list'

RSpec.describe Ammitto::Sources::Tr::Transformer do
  subject(:transformer) { described_class.new }

  def source(**attrs)
    Ammitto::Sources::Tr::SanctionedEntity.new(
      entity_type: 'organization',
      program: 'Law No. 7262, Articles 3.A/3.B',
      **attrs
    )
  end

  describe '#transform' do
    it 'mints numbered IRIs from the upstream reference number' do
      result = transformer.transform(
        source(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
               reference_number: '187')
      )

      expect(result[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/187')
      expect(result[:entry].id).to end_with('/187')
    end

    # A reference Turkey formatted with a decimal place mints an IRI like
    # any other reference. Roo returns a Float for a cell whose display
    # format carries decimals, so this is what a cosmetically reformatted
    # workbook delivers for every one of the 239 numbered rows.
    it 'mints an IRI from a decimally formatted number' do
      result = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: 1.0)
      )

      expect(result[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/10')
    end

    # The scope boundary, pinned. For a record that HAS a reference,
    # +local_id+ hands back that reference untouched, so the IRI is
    # whatever the reference alone has always minted. Every numbered
    # record therefore keeps the IRI it has today, and no reference shape
    # is addressed differently than before — the only identities this
    # change invents are for records that carry no reference at all.
    ['187', '1.0', 'TR-1', '12/A', '--', '١٢٣'].each do |reference|
      it "addresses #{reference.inspect} exactly as the reference alone does" do
        expected = begin
          Ammitto::Utils::IriSanitizer.entity_iri('tr', reference)
        rescue Ammitto::Utils::IriSanitizer::MissingLocalIdError
          :raised
        end
        actual = begin
          transformer.transform(
            source(name: 'TAMAS COMPANY', reference_number: reference)
          )[:entity].id
        rescue Ammitto::Utils::IriSanitizer::MissingLocalIdError
          :raised
        end

        expect(actual).to eq(expected)
      end
    end

    it 'mints an IRI from a reference that is not a bare number' do
      result = transformer.transform(
        source(name: 'MESBAH ENERGY COMPANY', reference_number: 'E.47.A.3')
      )

      expect(result[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/e47a3')
      expect(result[:entry].id).to end_with('/e47a3')
    end

    it 'mints a name-derived IRI when no reference number was published' do
      result = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: nil)
      )

      expect(result[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/tamas-company')
      expect(result[:entry].id).to end_with('/tamas-company')
    end

    it 'keeps the entry IRI aligned with the entity IRI' do
      result = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: nil)
      )

      local_id = result[:entity].id.split('/').last

      expect(result[:entry].entity_id).to eq(result[:entity].id)
      expect(result[:entry].id).to end_with("/#{local_id}")
    end

    it 'reports no reference number for records Turkey did not number' do
      result = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: nil)
      )

      reference = result[:entity].source_references.first

      expect(reference.source_code).to eq('tr')
      expect(reference.reference_number).to be_nil
    end

    it 'gives unnumbered person records distinct IRIs' do
      names = ['DAWOOD AGHA-JANI', 'AMIR MOAYYED ALAI', 'BEHMAN ASGARPOUR']

      ids = names.map do |name|
        transformer.transform(
          source(name: name, entity_type: 'person', reference_number: nil)
        )[:entity].id
      end

      expect(ids.uniq.size).to eq(3)
      expect(ids).to all(start_with('https://www.ammitto.org/entity/tr/'))
      expect(ids).to all(satisfy { |id| !id.end_with?('/unknown') })
    end

    # Crosses the serialization boundary the harvest actually crosses:
    # fetch writes YAML, harmonize reads it back. A surrogate that survives
    # that round trip unchanged is what "stable across harvests" means.
    it 'gives the same record the same IRI across a YAML round trip' do
      original = source(name: 'MESBAH ENERGY COMPANY', reference_number: nil)
      reloaded = Ammitto::Sources::Tr::Entity.from_yaml(original.to_yaml)

      expect(transformer.transform(reloaded)[:entity].id)
        .to eq(transformer.transform(original)[:entity].id)
    end

    it 'derives a stable IRI for representative unnumbered names' do
      names = ['DAWOOD AGHA-JANI', 'EHSAN MONAJEMİ', 'M. JAVAD KARIMI SABET',
               'ESFAHAN NUCLEAR FUEL RESEARCH AND PRODUCTION CENTRE ' \
               '(NFRPC) AND ESFAHAN NUCLEAR TECHNOLOGY CENTRE(ENTC)']

      ids = names.map do |name|
        transformer.transform(source(name: name, reference_number: nil))[:entity].id
      end

      expect(ids.uniq.size).to eq(names.size)
      expect(ids).to all(satisfy { |id| !id.end_with?('/unknown') })
    end

    it 'never mixes a name-derived id with a numbered one' do
      numbered = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: '187')
      )[:entity].id
      derived = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: nil)
      )[:entity].id

      expect(numbered).not_to eq(derived)
    end

    # The third case, and the one PR #28 exists to protect: a record with
    # no usable identifier at all fails loudly instead of joining every
    # other such record on one shared ".../unknown" node.
    it 'raises when neither the reference nor the name can identify it' do
      expect do
        transformer.transform(source(name: '  ', reference_number: nil))
      end.to raise_error(Ammitto::Utils::IriSanitizer::MissingLocalIdError,
                         /cannot build entity IRI/)
    end

    it 'raises for a reference that survives sanitization as nothing' do
      expect do
        transformer.transform(source(name: 'TAMAS COMPANY',
                                     reference_number: '--'))
      end.to raise_error(Ammitto::Utils::IriSanitizer::MissingLocalIdError,
                         /cannot build entity IRI/)
    end

    it 'raises rather than re-address an unreadable reference by name' do
      expect do
        transformer.transform(source(name: 'TAMAS COMPANY',
                                     reference_number: '١٢٣'))
      end.to raise_error(Ammitto::Utils::IriSanitizer::MissingLocalIdError)
    end
  end
end
