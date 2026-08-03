# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/tr'

RSpec.describe Ammitto::Sources::Tr::SanctionedEntity do
  def entity(name:, reference_number: nil)
    described_class.new(name: name, reference_number: reference_number)
  end

  def build(**attrs)
    described_class.new(name: 'TAMAS COMPANY', **attrs)
  end

  # The designee entity/tr/187 is already published for.
  def dtsrc(reference_number: '187')
    entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)',
           reference_number: reference_number)
  end

  # The designee Turkey gives the same number to, published nowhere.
  def dio(reference_number: '187')
    entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
           reference_number: reference_number)
  end

  describe '#local_id' do
    it 'is the reference Turkey published' do
      expect(entity(name: 'ACME', reference_number: '42').local_id)
        .to eq('42')
    end

    it 'ignores surrounding whitespace in the reference' do
      expect(entity(name: 'ACME', reference_number: ' 42 ').local_id)
        .to eq('42')
    end

    it 'passes a non-decimal reference through untouched' do
      expect(entity(name: 'ACME', reference_number: 'TR-1').local_id)
        .to eq('TR-1')
    end

    it 'prefers the upstream reference number' do
      record = build(name: 'TAMAS COMPANY', reference_number: '42')

      expect(record.local_id).to eq('42')
    end

    it 'falls back to the name when Turkey published no reference number' do
      record = build(name: 'TAMAS COMPANY', reference_number: nil)

      expect(record.local_id).to eq('TAMAS COMPANY')
    end

    it 'treats an empty reference number as absent' do
      record = build(name: 'TAMAS COMPANY', reference_number: '')

      expect(record.local_id).to eq('TAMAS COMPANY')
    end

    it 'treats a whitespace-only reference number as absent' do
      record = build(name: 'TAMAS COMPANY', reference_number: "  \t ")

      expect(record.local_id).to eq('TAMAS COMPANY')
    end

    # "Absent" means the cell is empty, not that it happens to sanitize to
    # nothing. A cell holding punctuation or non-Latin digits carries
    # content, so it is taken as published; refusing it is the IRI layer's
    # job, and it does so loudly (see the transformer spec).
    ['--', '!!', '١٢٣'].each do |unreadable|
      it "takes the unreadable reference #{unreadable.inspect} as given" do
        record = build(name: 'TAMAS COMPANY', reference_number: unreadable)

        expect(record.local_id).to eq(unreadable)
      end
    end

    it 'never re-addresses a present-but-unreadable cell by the name' do
      first = build(name: 'SAME NAME', reference_number: '--')
      second = build(name: 'SAME NAME', reference_number: '!!')

      expect([first.local_id, second.local_id]).to eq(['--', '!!'])
    end

    it 'strips surrounding whitespace from the reference number' do
      record = build(name: 'TAMAS COMPANY', reference_number: ' 42 ')

      expect(record.local_id).to eq('42')
    end

    it 'strips surrounding whitespace from the fallback name' do
      record = build(name: '  TAMAS COMPANY  ', reference_number: nil)

      expect(record.local_id).to eq('TAMAS COMPANY')
    end

    it 'returns nil when neither field can produce an IRI segment' do
      record = build(name: nil, reference_number: nil)

      expect(record.local_id).to be_nil
    end

    it 'returns nil when the name would sanitize away entirely' do
      record = build(name: 'محمد', reference_number: nil)

      expect(record.local_id).to be_nil
    end

    it 'refuses a list smuggled into the reference number slot' do
      record = build(name: 'TAMAS COMPANY', reference_number: [1])

      expect(record.local_id).to be_nil
    end

    # A mapping is stringified by the model layer before #local_id sees it,
    # so it arrives as an ordinary (odd) String and is indistinguishable
    # from an odd reference Turkey really published. It is accepted, and
    # the id it mints is deterministic — which is the property that
    # matters. A list is a different case: it reaches #local_id still a
    # list, so it can be told apart, and it is.
    it 'accepts a mapping the model already flattened to a string' do
      record = build(name: 'TAMAS COMPANY', reference_number: { a: 1 })

      expect(record.reference_number).to be_a(String)
      expect(record.local_id).to eq(record.reference_number)
    end

    it 'rejects a list smuggled into the name slot' do
      record = build(name: %w[TAMAS], reference_number: nil)

      expect(record.local_id).to be_nil
    end

    # An object the model stringified into Ruby's inspection form carries an
    # object address, so slugging it would mint a different IRI per process.
    it 'rejects a value stringified into Ruby inspection form' do
      record = build(name: [1].each, reference_number: nil)

      expect(record.name).to start_with('#<')
      expect(record.local_id).to be_nil
    end

    it 'refuses an inspection form in the reference number slot' do
      record = build(name: 'TAMAS COMPANY', reference_number: [1].each)

      expect(record.local_id).to be_nil
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
      record = build(name: 'TAMAS COMPANY', reference_number: 42)

      expect(record.local_id).to eq('42')
    end

    # The second road a reference travels. Harmonize re-reads a record
    # file rather than the sheet, so a file an earlier fetch wrote as
    # "1.0" would mint entity/tr/10 — reference 10's IRI — unless this
    # method reduces the two spellings to one the way the sheet does.
    it 'reads a redundantly spelled whole number as that number' do
      record = build(name: 'TAMAS COMPANY', reference_number: '1.0')

      expect(record.local_id).to eq('1')
    end

    it 'reads either spelling of a number identically' do
      spelled = build(name: 'A', reference_number: '1.0').local_id
      plain = build(name: 'A', reference_number: '1').local_id

      expect(spelled).to eq(plain)
    end

    it 'keeps a redundantly spelled number off another record number' do
      first = build(name: 'FIRST', reference_number: '1.0')
      second = build(name: 'SECOND', reference_number: '10')

      expect([first.local_id, second.local_id]).to eq(%w[1 10])
    end

    # Exactly the redundant fraction comes off, and nothing else. Reading
    # the digits as a number would also drop leading zeros and split one
    # designee across two IRIs on the very difference this erases.
    it 'removes the fraction without disturbing leading zeros' do
      spelled = build(name: 'A', reference_number: '01.0').local_id
      plain = build(name: 'A', reference_number: '01').local_id

      expect(spelled).to eq('01')
      expect(spelled).to eq(plain)
    end

    it 'leaves reference_number reporting what the record holds' do
      record = build(name: 'TAMAS COMPANY', reference_number: '1.0')

      expect(record.reference_number).to eq('1.0')
      expect(record.local_id).to eq('1')
    end

    # A fractional value is a different number, not a spelling of a whole
    # one, so it passes through untouched.
    it 'leaves a genuinely fractional reference alone' do
      record = build(name: 'TAMAS COMPANY', reference_number: '1.5')

      expect(record.local_id).to eq('1.5')
    end

    ['-10', '10-', '--10--'].each do |rewritten|
      it "accepts #{rewritten.inspect} rather than losing the record" do
        record = build(name: 'TAMAS COMPANY', reference_number: rewritten)

        expect(record.local_id).to eq(rewritten)
      end
    end

    it 'strips a rewritten reference the same way as a plain one' do
      record = build(name: 'TAMAS COMPANY', reference_number: ' -10 ')

      expect(record.local_id).to eq('-10')
    end

    # No opinion is taken on what a well-formed "Sıra No" looks like. 14 of
    # the 37 unnumbered rows already cite a prior designation in their
    # remarks prose ("Eski Referans No. E.47.A.3"); reading those out is
    # deferred, but a bare-decimal rule could never have used one.
    ['12/A', '12A', '12 A', 'ABC', '1 0', 'TR-1', 'E.47.A.3'].each do |odd|
      it "accepts the non-decimal reference #{odd.inspect}" do
        record = build(name: 'TAMAS COMPANY', reference_number: odd)

        expect(record.local_id).to eq(odd)
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
      record = build(name: 'SAME NAME', reference_number: nil)

      expect(record.local_id).to eq('SAME NAME')
    end

    it 'refuses a name that would sanitize to a bare number' do
      record = build(name: '187', reference_number: nil)

      expect(record.local_id).to be_nil
    end

    it 'does not invent a reference number for records that lack one' do
      record = build(name: 'TAMAS COMPANY', reference_number: nil)

      expect(record.local_id).not_to be_nil
      expect(record.reference_number).to be_nil
    end

    context 'when the reference is reserved for a published designee' do
      it 'keeps the number for the designee the IRI already denotes' do
        expect(dtsrc.local_id).to eq('187')
      end

      it 'gives the other claimant a name-derived id instead' do
        expect(dio.local_id).to eq('DEFENCE INDUSTRIES ORGANISATION (DIO)')
      end

      it 'resolves the same way whichever row is inspected first' do
        forwards = [dtsrc, dio].map(&:local_id)
        backwards = [dio, dtsrc].map(&:local_id).reverse

        expect(forwards).to eq(backwards)
        expect(forwards).to eq(['187',
                                'DEFENCE INDUSTRIES ORGANISATION (DIO)'])
      end

      it 'reserves the number even when nothing else claims it' do
        # A tie-break that only fired on a duplicate would let the other
        # designee inherit a published IRI the moment the holder was
        # renumbered away.
        expect(dio.local_id).not_to eq('187')
      end

      it 'leaves the holder alone under any other reference' do
        expect(dtsrc(reference_number: '900').local_id).to eq('900')
      end

      it 'refuses a name that would land in Turkey\'s own numbering' do
        # Otherwise a designee named "42" would take entity/tr/42 from
        # whoever Turkey numbered 42.
        expect(entity(name: '42', reference_number: '187').local_id).to be_nil
      end

      it 'is nil when the claimant carries no name to fall back to' do
        expect(entity(name: '  ', reference_number: '187').local_id).to be_nil
      end

      # Where the two fixes meet. The reservation is keyed on the
      # identifier the record would MINT, so a workbook — or a record file
      # an earlier fetch wrote — that spells 187 as "187.0" still hands
      # entity/tr/187 to the same designee.
      it 'reads a redundantly spelled reserved number as reserved' do
        expect(dtsrc(reference_number: '187.0').local_id).to eq('187')
        expect(dio(reference_number: '187.0').local_id)
          .to eq('DEFENCE INDUSTRIES ORGANISATION (DIO)')
      end

      it 'resolves either spelling of the reserved number identically' do
        spelled = [dtsrc(reference_number: '187.0'),
                   dio(reference_number: '187.0')].map(&:local_id)
        plain = [dtsrc, dio].map(&:local_id)

        expect(spelled).to eq(plain)
      end

      # A reservation is about one ADDRESS, not about every text that looks
      # like the number: 1870 mints entity/tr/1870, which is nobody's
      # reserved address, so it stays its own.
      it 'does not spread the reservation to a neighbouring number' do
        expect(dio(reference_number: '1870').local_id).to eq('1870')
      end

      # The same rule read the other way, and the reason the lookup is on
      # the minted segment rather than the text. None of these spells 187,
      # so a reservation comparing text would wave all three through — but
      # sanitization drops the dot and the edge hyphens, so every one of
      # them lands on entity/tr/187, the address already published for
      # DTSRC. A row that is not DTSRC therefore falls back to its name.
      %w[-187 187- 18.7 1.87].each do |spelling|
        it "treats #{spelling.inspect} as reaching the reserved address" do
          expect(described_class.reference_segment(spelling)).to eq('187')
          expect(dio(reference_number: spelling).local_id)
            .to eq('DEFENCE INDUSTRIES ORGANISATION (DIO)')
        end

        it "still lets DTSRC keep #{spelling.inspect}" do
          expect(dtsrc(reference_number: spelling).local_id).to eq(spelling)
        end
      end
    end
  end

  describe '.reference_segment' do
    it 'is the address a published reference lands on' do
      expect(described_class.reference_segment('187')).to eq('187')
    end

    # Both steps, in the order identity applies them: the redundant
    # spelling comes off first, then the sanitizer.
    it 'reduces the spelling before sanitizing' do
      expect(described_class.reference_segment('187.0')).to eq('187')
    end

    it 'is nil for a reference that mints no address at all' do
      expect(described_class.reference_segment('--')).to be_nil
      expect(described_class.reference_segment(nil)).to be_nil
    end
  end

  describe 'RESERVED_LOCAL_IDS' do
    it 'pins the reference to the sanitized name of its published holder' do
      holder = described_class::RESERVED_LOCAL_IDS.fetch('187')

      expect(Ammitto::Utils::IriSanitizer.sanitize(dtsrc.name))
        .to eq(holder[:slug])
    end

    it 'also pins the holder name at full fidelity' do
      # The slug drops the "Ç"; this form is what tells the holder from a
      # different designee whose name sanitizes onto the same slug.
      holder = described_class::RESERVED_LOCAL_IDS.fetch('187')

      expect(described_class.strict_name(dtsrc.name)).to eq(holder[:name])
    end

    it 'cannot drift at runtime, entries included' do
      # Freezing the table alone would still let `table[ref][:slug]`
      # be reassigned, moving a published IRI to a different designee.
      table = described_class::RESERVED_LOCAL_IDS

      expect(table).to be_frozen
      expect(table.keys).to all(be_frozen)
      expect(table.values).to all(be_frozen)
      expect { table.fetch('187')[:slug] = 'other' }
        .to raise_error(FrozenError)
      expect { table.fetch('187')[:slug].replace('other') }
        .to raise_error(FrozenError)
    end

    it 'is keyed on minted segments, so no entry can be unreachable' do
      # local_id looks the table up by the address a reference lands on,
      # so a key must BE an address. A key spelled "187.0" or "-187"
      # names one without being one: it would never be found, and the IRI
      # it protects would move to whoever arrived there next.
      keys = described_class::RESERVED_LOCAL_IDS.keys

      expect(keys).to all(satisfy do |key|
        described_class.minted_segment(key) == key
      end)
    end
  end

  # The rule #local_id applies on the record-file road. The sheet road
  # uses .exact_integer_text instead, which SanctionsList.cell_text
  # exercises, because there the artefact is a Float and a text cell must
  # survive verbatim.
  describe '.whole_decimal_text' do
    it 'reduces a redundantly spelled number to its digits' do
      expect(described_class.whole_decimal_text('1.0')).to eq('1')
      expect(described_class.whole_decimal_text('1.00')).to eq('1')
    end

    it 'removes the fraction and nothing else' do
      expect(described_class.whole_decimal_text('01.0')).to eq('01')
      expect(described_class.whole_decimal_text('-0.0')).to eq('-0')
    end

    # Text carries the workbook's own digits rather than a Float's
    # approximation of them, so no precision limit applies here.
    it 'keeps every digit of a long number' do
      expect(described_class.whole_decimal_text('9007199254740993.0'))
        .to eq('9007199254740993')
    end

    it 'leaves text that does not spell a whole number alone' do
      ['1.5', 'E.47.A.3', '12/A', '1.0e3', '1.', '+1.0', '١٢٣.0']
        .each do |text|
          expect(described_class.whole_decimal_text(text)).to be_nil
        end
    end

    # Float#to_s changes shape at 1e15, so a record file an earlier fetch
    # wrote carries the same artefact in two spellings. Recognising only
    # the "1000.0" one would leave the two roads disagreeing exactly where
    # MAX_SAFE_INTEGER still calls the value exact.
    it "expands Ruby's scientific rendering of a whole number" do
      expect(described_class.whole_decimal_text('1.0e+15'))
        .to eq('1000000000000000')
      expect(described_class.whole_decimal_text('-1.0e+15'))
        .to eq('-1000000000000000')
    end

    it 'stops at the same magnitude the sheet road stops at' do
      # 2**53 and beyond: neither road rewrites, so both already agree.
      expect(described_class.whole_decimal_text('9.007199254740992e+15'))
        .to be_nil
      expect(described_class.whole_decimal_text('1.0e+20')).to be_nil
    end

    it 'expands the largest magnitude that is still exact' do
      expect(described_class.whole_decimal_text('9.007199254740991e+15'))
        .to eq('9007199254740991')
    end

    # Only Ruby's own rendering, not scientific notation in general: a
    # published reference of "1E5" is an identifier Turkey wrote, and
    # rewriting it to "100000" would invent data.
    it 'leaves a hand-written exponent alone' do
      # "0.5e+3" belongs here too: Ruby normalizes the mantissa and never
      # writes a leading zero, so that spelling is somebody's own text.
      ['1E5', '1e5', '12.5e3', '1.0E+15', '0.5e+3'].each do |text|
        expect(described_class.whole_decimal_text(text)).to be_nil
      end
    end

    # These name the very number the expansion would produce and still do
    # not get it, because they are not what Ruby prints. Only an exact
    # round trip counts; a pattern that merely looks right would rewrite
    # a reference Turkey published.
    it "leaves a near-miss of Ruby's own rendering alone" do
      ['1.00e+15', '1.0e+015', '-0.0e+00'].each do |text|
        expect(described_class.whole_decimal_text(text)).to be_nil
      end
    end
  end

  # The two roads a reference travels must arrive at one ADDRESS. The
  # sheet hands identity a Float; a record file hands it that Float's
  # text. What has to match is where they land, not the text they carry
  # there — -0.0 reaches the sanitizer as "0" from the sheet and "-0"
  # from the file, and both mint entity/tr/0, which is the whole claim.
  describe 'agreement between the sheet road and the record-file road' do
    [1.0, 999_999_999_999_999.0, 1.0e15, (2.0**53) - 1, 2.0**53, 1.0e20,
     1.5, -1.0e15, 0.0, -0.0, -1.0].each do |float|
      it "mints one address for #{float.inspect} however it arrives" do
        sheet = Ammitto::Sources::Tr::SanctionsList.cell_text(float)
        record = float.to_s

        expect(described_class.reference_segment(sheet))
          .to eq(described_class.reference_segment(record))
      end
    end
  end

  # What identity reads a reference as. The corpus gates in SanctionsList
  # read it through this method too, so a gate and the IRI layer can never
  # disagree about which record claims a number.
  describe '.canonical_reference' do
    it 'reduces a redundantly spelled number to its digits' do
      expect(described_class.canonical_reference('187.0')).to eq('187')
    end

    it 'strips surrounding whitespace' do
      expect(described_class.canonical_reference(' 187 ')).to eq('187')
    end

    it 'leaves a reference that spells no whole number alone' do
      expect(described_class.canonical_reference('E.47.A.3')).to eq('E.47.A.3')
      expect(described_class.canonical_reference('1.5')).to eq('1.5')
    end

    it 'reads an absent reference as the empty string' do
      expect(described_class.canonical_reference(nil)).to eq('')
    end
  end

  describe '.exact_integer_text' do
    it 'reduces a Float that provably holds one integer' do
      expect(described_class.exact_integer_text(1.0)).to eq('1')
    end

    it 'refuses anything that is not a Float' do
      expect(described_class.exact_integer_text('1.0')).to be_nil
      expect(described_class.exact_integer_text(1)).to be_nil
    end

    it 'refuses a Float that names no single integer' do
      [1.5, 2.0**53, 1.0e20, Float::INFINITY, Float::NAN].each do |value|
        expect(described_class.exact_integer_text(value)).to be_nil
      end
    end
  end
end
