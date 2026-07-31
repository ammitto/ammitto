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
    # content, so it is taken as published; refusing it is the IRI layer's
    # job, and it does so loudly (see the transformer spec).
    ['--', '!!', '١٢٣'].each do |unreadable|
      it "takes the unreadable reference #{unreadable.inspect} as given" do
        entity = build(name: 'TAMAS COMPANY', reference_number: unreadable)

        expect(entity.local_id).to eq(unreadable)
      end
    end

    it 'never re-addresses a present-but-unreadable cell by the name' do
      first = build(name: 'SAME NAME', reference_number: '--')
      second = build(name: 'SAME NAME', reference_number: '!!')

      expect([first.local_id, second.local_id]).to eq(['--', '!!'])
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
    # so it arrives as an ordinary (odd) String and is indistinguishable
    # from an odd reference Turkey really published. It is accepted, and
    # the id it mints is deterministic — which is the property that
    # matters. A list is a different case: it reaches #local_id still a
    # list, so it can be told apart, and it is.
    it 'accepts a mapping the model already flattened to a string' do
      entity = build(name: 'TAMAS COMPANY', reference_number: { a: 1 })

      expect(entity.reference_number).to be_a(String)
      expect(entity.local_id).to eq(entity.reference_number)
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

    # The motivating case. Turkey's numbers reach the parser through Roo,
    # which hands back a Float for a numeric cell, so whether a row reads
    # "1" or "1.0" is decided by the workbook's display format rather than
    # by its value. A rule that accepted only bare decimals would drop all
    # 239 numbered records the day Turkey re-uploaded the same numbers
    # formatted with a decimal place.
    it 'keeps a decimally formatted number usable' do
      entity = build(name: 'TAMAS COMPANY', reference_number: 1.0)

      expect(entity.local_id).to eq('1.0')
      expect(Ammitto::Utils::IriSanitizer.sanitize(entity.local_id))
        .to eq('10')
    end

    ['1.0', '-10', '10-', '--10--'].each do |rewritten|
      it "accepts #{rewritten.inspect} rather than losing the record" do
        entity = build(name: 'TAMAS COMPANY', reference_number: rewritten)

        expect(entity.local_id).to eq(rewritten)
      end
    end

    it 'strips a rewritten reference the same way as a plain one' do
      entity = build(name: 'TAMAS COMPANY', reference_number: ' -10 ')

      expect(entity.local_id).to eq('-10')
    end

    # No opinion is taken on what a well-formed "Sıra No" looks like. The
    # 14 unnumbered rows citing an "Eski Referans No" such as "E.47.A.3"
    # are the shape this most obviously has to leave room for.
    ['12/A', '12A', '12 A', 'ABC', '1 0', 'TR-1', 'E.47.A.3'].each do |odd|
      it "accepts the non-decimal reference #{odd.inspect}" do
        entity = build(name: 'TAMAS COMPANY', reference_number: odd)

        expect(entity.local_id).to eq(odd)
      end
    end

    # Two references sanitizing onto one segment is a real consequence of
    # accepting every shape, and it is deliberately not decided here: one
    # record cannot see another, so distinctness is a corpus-level gate.
    # What this method does guarantee is that neither record is silently
    # re-addressed by its name, which is what would merge them.
    it 'accepts two references that sanitize onto one segment' do
      first = build(name: 'SAME NAME', reference_number: '12/A')
      second = build(name: 'SAME NAME', reference_number: '12A')

      expect([first.local_id, second.local_id]).to eq(['12/A', '12A'])
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
