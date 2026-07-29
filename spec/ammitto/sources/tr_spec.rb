# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/tr/sanctions_list'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Sources::Tr::SanctionedEntity do
  def build(**attrs)
    described_class.new(name: 'TAMAS COMPANY', **attrs)
  end

  describe '#local_id' do
    it 'prefers the upstream reference number' do
      entity = build(name: 'TAMAS COMPANY', reference_number: '187')

      expect(entity.local_id).to eq('187')
    end

    it 'falls back to the name when Turkey published no reference number' do
      entity = build(name: 'TAMAS COMPANY', reference_number: nil)

      expect(entity.local_id).to eq('TAMAS COMPANY')
    end

    it 'treats an empty reference number as absent' do
      entity = build(name: 'TAMAS COMPANY', reference_number: '')

      expect(entity.local_id).to eq('TAMAS COMPANY')
    end

    it 'treats a whitespace-only reference number as absent' do
      entity = build(name: 'TAMAS COMPANY', reference_number: "  \t ")

      expect(entity.local_id).to eq('TAMAS COMPANY')
    end

    it 'treats a punctuation-only reference number as absent' do
      entity = build(name: 'TAMAS COMPANY', reference_number: '--')

      expect(entity.local_id).to eq('TAMAS COMPANY')
    end

    it 'strips surrounding whitespace from the reference number' do
      entity = build(name: 'TAMAS COMPANY', reference_number: ' 187 ')

      expect(entity.local_id).to eq('187')
    end

    it 'strips surrounding whitespace from the fallback name' do
      entity = build(name: '  TAMAS COMPANY  ', reference_number: nil)

      expect(entity.local_id).to eq('TAMAS COMPANY')
    end

    it 'returns nil when neither field can produce an IRI segment' do
      entity = build(name: nil, reference_number: nil)

      expect(entity.local_id).to be_nil
    end

    it 'returns nil when the name would sanitize away entirely' do
      entity = build(name: 'محمد', reference_number: nil)

      expect(entity.local_id).to be_nil
    end

    it 'refuses a list smuggled into the reference number slot' do
      entity = build(name: 'TAMAS COMPANY', reference_number: [1])

      expect(entity.local_id).to be_nil
    end

    # A mapping is stringified by the model layer before #local_id sees it,
    # so it arrives as an ordinary (odd) String. It carries content but is
    # not one of Turkey's numbers, so the record is refused rather than
    # quietly re-addressed by its name.
    it 'refuses a mapping in the reference number slot' do
      entity = build(name: 'TAMAS COMPANY', reference_number: { a: 1 })

      expect(entity.local_id).to be_nil
    end

    it 'rejects a list smuggled into the name slot' do
      entity = build(name: %w[TAMAS], reference_number: nil)

      expect(entity.local_id).to be_nil
    end

    # An object the model stringified into Ruby's inspection form carries an
    # object address, so slugging it would mint a different IRI per process.
    it 'rejects a value stringified into Ruby inspection form' do
      entity = build(name: [1].each, reference_number: nil)

      expect(entity.name).to start_with('#<')
      expect(entity.local_id).to be_nil
    end

    it 'refuses an inspection form in the reference number slot' do
      entity = build(name: 'TAMAS COMPANY', reference_number: [1].each)

      expect(entity.local_id).to be_nil
    end

    # A corrupt reference is evidence the record is broken, not evidence
    # that Turkey left the cell empty, so it must never be re-addressed by
    # the name — two same-named corrupt records would merge into one node.
    it 'refuses same-named records carrying different bad containers' do
      first = build(name: 'SAME NAME', reference_number: [1])
      second = build(name: 'SAME NAME', reference_number: [2])

      expect(first.local_id).to be_nil
      expect(second.local_id).to be_nil
    end

    it 'refuses same-named records carrying different inspection forms' do
      first = build(name: 'SAME NAME', reference_number: '#<Enumerator:0x1>')
      second = build(name: 'SAME NAME', reference_number: '#<Enumerator:0x2>')

      expect(first.local_id).to be_nil
      expect(second.local_id).to be_nil
    end

    it 'accepts a numeric reference number cast from the spreadsheet' do
      entity = build(name: 'TAMAS COMPANY', reference_number: 187)

      expect(entity.local_id).to eq('187')
    end

    it 'refuses a reference number sanitization would rewrite' do
      entity = build(name: 'TAMAS COMPANY', reference_number: '1.0')

      expect(entity.local_id).to be_nil
    end

    ['-10', '10-', '--10--', ' -10 '].each do |hostile|
      it "refuses #{hostile.inspect}, which sanitizes onto record 10" do
        entity = build(name: 'TAMAS COMPANY', reference_number: hostile)

        expect(entity.local_id).to be_nil
      end
    end

    # Turkey publishes plain ASCII decimal numbers. Anything else is not a
    # reference we can trust, because sanitization can rewrite two distinct
    # values onto one segment ("12/A" and "12A" both become "12a"). Such a
    # record is refused outright rather than re-addressed by its name, so
    # that two of them sharing a name cannot merge into one node.
    ['12/A', '12A', '12 A', 'ABC', '1 0'].each do |odd|
      it "refuses non-decimal reference #{odd.inspect}" do
        entity = build(name: 'TAMAS COMPANY', reference_number: odd)

        expect(entity.local_id).to be_nil
      end
    end

    it 'refuses same-named records carrying different bad references' do
      first = build(name: 'SAME NAME', reference_number: '12/A')
      second = build(name: 'SAME NAME', reference_number: '12A')

      expect(first.local_id).to be_nil
      expect(second.local_id).to be_nil
    end

    it 'still falls back to the name when no reference was published' do
      entity = build(name: 'SAME NAME', reference_number: nil)

      expect(entity.local_id).to eq('SAME NAME')
    end

    it 'refuses a name that would sanitize to a bare number' do
      entity = build(name: '187', reference_number: nil)

      expect(entity.local_id).to be_nil
    end

    it 'does not invent a reference number for records that lack one' do
      entity = build(name: 'TAMAS COMPANY', reference_number: nil)

      expect(entity.local_id).not_to be_nil
      expect(entity.reference_number).to be_nil
    end
  end
end

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

    it 'does not let a list in the reference number slot steal an IRI' do
      stolen = transformer.transform(
        source(name: 'TAMAS COMPANY', reference_number: [1])
      )[:entity].id
      real = transformer.transform(
        source(name: 'YUN HO-JIN', reference_number: '1')
      )[:entity].id

      expect(stolen).not_to eq(real)
      expect(stolen).not_to eq('https://www.ammitto.org/entity/tr/tamas-company')
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
  end
end

# Enters at Cmd::HarmonizeCommand#transform_data, so the assertions cover the
# transformer-registry lookup and the :tr routing branch as well as the
# transformation and its JSON-LD serialization. Input is the parsed shape of a
# record file the fetcher committed to data-tr.
RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  subject(:command) { described_class.new({}, [:tr]) }

  def harmonize(record)
    command.send(:transform_data, :tr, record)
  end

  let(:numbered) do
    { 'name' => 'YUN HO-JIN',
      'entity_type' => 'person',
      'program' => 'Law No. 7262, Articles 3.A/3.B',
      'listed_date' => '24.2.2021/ 3578',
      'reference_number' => '1' }
  end

  let(:unnumbered) do
    { 'name' => 'DAWOOD AGHA-JANI',
      'entity_type' => 'person',
      'program' => 'Law No. 7262, Articles 3.A/3.B',
      'place_of_birth' => 'Ardebil, İran' }
  end

  describe '#transform_data' do
    it 'keeps the numbered record on its published IRI' do
      expect(harmonize(numbered)[:entity]['@id'])
        .to eq('https://www.ammitto.org/entity/tr/1')
    end

    it 'gives the unnumbered record its own IRI, not the placeholder' do
      expect(harmonize(unnumbered)[:entity]['@id'])
        .to eq('https://www.ammitto.org/entity/tr/dawood-agha-jani')
    end

    it 'does not let the unnumbered record collide with a numbered one' do
      expect(harmonize(unnumbered)[:entity]['@id'])
        .not_to eq(harmonize(numbered)[:entity]['@id'])
    end

    it 'points the serialized entry at the same entity' do
      result = harmonize(unnumbered)

      expect(result[:entry]['@id']).to end_with('/dawood-agha-jani')
      expect(result[:entry]['entityId']).to eq(result[:entity]['@id'])
    end

    it 'emits no reference number for a record Turkey did not number' do
      reference = harmonize(unnumbered)[:entity]['sourceReferences'].first

      expect(reference['sourceCode']).to eq('tr')
      expect(reference).not_to have_key('referenceNumber')
    end

    it 'still emits the reference number Turkey did publish' do
      reference = harmonize(numbered)[:entity]['sourceReferences'].first

      expect(reference['referenceNumber']).to eq('1')
    end

    it 'routes an unnumbered record to its own name-derived entity' do
      other = unnumbered.merge('name' => 'AMIR MOAYYED ALAI')

      expect(harmonize(other)[:entity]['@id'])
        .to eq('https://www.ammitto.org/entity/tr/amir-moayyed-alai')
      expect(harmonize(other)[:entity]['@id'])
        .not_to eq(harmonize(unnumbered)[:entity]['@id'])
    end
  end
end
