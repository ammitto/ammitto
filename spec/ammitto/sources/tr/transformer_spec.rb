# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/tr'

# The fetch fix alone would keep both designees on disk and still lose one
# in the graph: harmonize reads each YAML file back and mints its IRIs
# here. These examples pin the graph half of that seam — that the
# transformer identifies a record by the same local_id the fetcher named
# its file after, so a record with its own file also gets its own node.
#
# Two defects meet in this class, and both are pinned below. Turkey gives
# one "Sıra No" to two organisations, so a number does not identify a
# record; and Turkey leaves the column blank on 37 rows, so a number is
# not always there to identify one with.
RSpec.describe Ammitto::Sources::Tr::Transformer do
  subject(:transformer) { described_class.new }

  # Turkey's two organisations on "Sıra No" 187. The first is the one
  # already published as entity/tr/187.
  def dtsrc
    entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)')
  end

  def dio
    entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)')
  end

  def entity(name:, reference_number: '187')
    Ammitto::Sources::Tr::SanctionedEntity.new(
      name: name, reference_number: reference_number,
      entity_type: 'entity'
    )
  end

  def source(**attrs)
    Ammitto::Sources::Tr::SanctionedEntity.new(
      entity_type: 'organization',
      program: 'Law No. 7262, Articles 3.A/3.B',
      **attrs
    )
  end

  def transform(record)
    described_class.new.transform(record)
  end

  describe 'two organisations sharing one reference' do
    it 'gives each its own entity IRI' do
      ids = [dtsrc, dio].map { |src| transform(src)[:entity].id }

      expect(ids.uniq.size).to eq(2)
    end

    it 'gives each its own entry IRI' do
      ids = [dtsrc, dio].map { |src| transform(src)[:entry].id }

      expect(ids.uniq.size).to eq(2)
    end

    it 'leaves entity/tr/187 on the designee already published there' do
      expect(transform(dtsrc)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/187')
    end

    it 'does not let the other designee take that IRI' do
      expect(transform(dio)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/' \
               'defence-industries-organisation-dio')
    end

    it 'points each entry at its own entity' do
      [dtsrc, dio].each do |record|
        result = transform(record)

        expect(result[:entry].entity_id).to eq(result[:entity].id)
      end
    end

    # The two fixes composed. A record file an earlier fetch wrote, before
    # the sheet reader canonicalized anything, still spells the reserved
    # number "187.0" — and the reservation has to recognise it, or
    # entity/tr/187 goes to whichever designee happens to carry the
    # decimal spelling.
    it 'resolves the reservation through a redundantly spelled number' do
      holder = entity(
        name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)',
        reference_number: '187.0'
      )
      other = entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
                     reference_number: '187.0')

      expect(transform(holder)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/187')
      expect(transform(other)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/' \
               'defence-industries-organisation-dio')
    end
  end

  describe 'provenance' do
    it 'keeps the number Turkey published on both records' do
      references = [dtsrc, dio].map do |record|
        transform(record)[:entity].source_references
                                  .map(&:reference_number)
      end

      expect(references).to all(include('187'))
    end
  end

  it 'mints an IRI from the reference where none is reserved' do
    record = entity(name: 'SOME ORGANISATION', reference_number: '42')

    expect(transform(record)[:entity].id)
      .to eq('https://www.ammitto.org/entity/tr/42')
  end

  # Persons take a different branch of create_entity, so the organisation
  # examples above cannot speak for this call site.
  describe 'persons' do
    def person(name:, reference_number: '187')
      Ammitto::Sources::Tr::SanctionedEntity.new(
        name: name, reference_number: reference_number,
        entity_type: 'person'
      )
    end

    it 'mints a person IRI from local_id, not the raw reference' do
      # A person cannot hold the organisation's reserved 187, so local_id
      # falls back to the name — and the IRI has to follow it.
      record = person(name: 'SOME PERSON')

      expect(transform(record)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/some-person')
    end

    it 'mints a person IRI from the reference where none is reserved' do
      record = person(name: 'SOME PERSON', reference_number: '42')

      expect(transform(record)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/42')
    end
  end

  describe '#transform' do
    it 'mints numbered IRIs from the upstream reference number' do
      # An ordinary, unreserved number. 187 is Turkey's one collision and
      # takes the reservation branch instead — see the group above.
      result = transformer.transform(
        source(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
               reference_number: '42')
      )

      expect(result[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/42')
      expect(result[:entry].id).to end_with('/42')
    end

    # A workbook Turkey reformats with decimals must keep every designee
    # on the number Turkey published. SanctionsList.cell_text is what
    # guarantees that, by undoing Roo's display-format artefact before the
    # value ever reaches a record; the parse-layer spec drives the sheet
    # itself. This pins the consequence the graph sees.
    it 'keeps a reformatted workbook on its published numbers' do
      minted = Ammitto::Sources::Tr::SanctionsList
               .cell_text(1.0)
               .then { |reference| source(name: 'A', reference_number: reference) }
               .then { |record| transformer.transform(record)[:entity].id }

      expect(minted).to eq('https://www.ammitto.org/entity/tr/1')
    end

    # The scope boundary, pinned for representative scalar references.
    # For a record that HAS one, +local_id+ delegates to it, so the IRI is
    # whatever that reference alone mints — including when it mints
    # nothing and the record is refused. The identities this change
    # invents are for records carrying no reference at all.
    #
    # Scalar references only, unreserved, and not a redundantly spelled
    # whole number: a container or an inspection-form string is
    # deliberately refused instead (see +malformed?+), a reserved number
    # is deliberately re-addressed by name (the group above), "1.0" is
    # deliberately reduced to "1" (the example above), and surrounding
    # whitespace is stripped, which the sanitizer would have collapsed
    # anyway.
    ['42', 'TR-1', '12/A', '--', '١٢٣'].each do |reference|
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
        source(name: 'TAMAS COMPANY', reference_number: '42')
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
