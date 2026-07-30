# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/tr/sanctions_list'

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

    # "Absent" means the cell is empty, not that it happens to sanitize to
    # nothing. A cell holding punctuation or non-Latin digits carries
    # content we cannot read, so the record is refused rather than
    # re-addressed by its name.
    ['--', '!!', '١٢٣'].each do |unreadable|
      it "refuses the unreadable reference #{unreadable.inspect}" do
        entity = build(name: 'TAMAS COMPANY', reference_number: unreadable)

        expect(entity.local_id).to be_nil
      end
    end

    it 'refuses same-named records carrying different unreadable cells' do
      first = build(name: 'SAME NAME', reference_number: '--')
      second = build(name: 'SAME NAME', reference_number: '!!')

      expect(first.local_id).to be_nil
      expect(second.local_id).to be_nil
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
    ['12/A', '12A', '12 A', 'ABC', '1 0', 'TR-1'].each do |odd|
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
