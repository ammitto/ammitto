# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/tr'
require 'ammitto/sources/tr/transformer'

RSpec.describe Ammitto::Sources::Tr::SanctionsList do
  # Turkey's List D header row, verbatim, as published 2026-07-30.
  LIVE_HEADERS = [
    'Sıra No', 'Gerçek Kişi Soyadı Ünvanı ', 'Eski Adı',
    'Tüzel Kuruluş/Organizasyon Ünvanı ', 'Kullandığı Bilinen Diğer İsmler',
    "\nPasaport No/ Diğer Muhtelif  Bilgiler \n", 'Görevi', 'Adres',
    'Uyruğu', 'Listeye Alınma Tarihi', 'Diğer Bilgiler', 'Doğum yeri',
    'Anne Adı', 'Baba Adı', 'Doğum Tarihi', 'Örgütü',
    'R.Gazete Tarih Sayı', 'BKK-CBK Karar Tarih ve Sayısı'
  ].freeze

  # A three-column subset, also Turkey's own titles, for the examples that
  # care about what Roo HANDS BACK for a numeric cell rather than about
  # the header row.
  NUMERIC_HEADERS = ['Sıra No', 'Gerçek Kişi Adı Soyadı',
                     'Pasaport No'].freeze

  # Minimal stand-in for a Roo sheet: the parser only asks for rows and
  # the last row number.
  def sheet_for(headers, rows)
    instance_double(Roo::Excelx::Sheet).tap do |sheet|
      allow(sheet).to receive(:row) do |n|
        n == 1 ? headers : rows[n - 2]
      end
      allow(sheet).to receive(:last_row).and_return(rows.size + 1)
    end
  end

  # Drives the real .from_xlsx. Roo is stubbed rather than a workbook
  # written to disk, because the whole point is what Roo hands back for a
  # numeric cell — Integer or Float according to the cell's display
  # format — and that is exactly the seam a fixture file would hide.
  def parse(headers, rows)
    sheet = sheet_for(headers, rows)
    allow(Roo::Excelx).to receive(:new)
      .and_return(instance_double(Roo::Excelx, sheet: sheet))

    described_class.from_xlsx('ignored.xlsx')
  end

  def references(*rows)
    parse(NUMERIC_HEADERS, rows).entities.map(&:reference_number)
  end

  def iris(*rows)
    transformer = Ammitto::Sources::Tr::Transformer.new
    parse(NUMERIC_HEADERS, rows).entities.map do |record|
      transformer.transform(record)[:entity].id
    end
  end

  def entity(name:, reference_number: nil)
    Ammitto::Sources::Tr::SanctionedEntity.new(
      name: name, reference_number: reference_number
    )
  end

  describe '.normalize_header' do
    it 'maps nationality, whose "ğ" the cleanup strips' do
      # "Uyruğu" arrives as "uyruu", so a pattern anchored on "uyruk"
      # never matched and every record lost its nationality.
      expect(described_class.normalize_header('Uyruğu')).to eq(:nationality)
    end

    it 'gives each of the four dated columns its own field' do
      dated = {
        'Listeye Alınma Tarihi' => :listed_date,
        'Doğum Tarihi' => :date_of_birth,
        'R.Gazete Tarih Sayı' => :official_gazette,
        'BKK-CBK Karar Tarih ve Sayısı' => :decision_number
      }

      actual = dated.keys.to_h do |header|
        [header, described_class.normalize_header(header)]
      end

      expect(actual).to eq(dated)
    end

    it 'maps every live column to the field it belongs in' do
      # Pinning the whole row, not just its uniqueness: distinct but
      # wrong destinations would corrupt records just as silently.
      expected = %i[
        reference_number name former_name organization_name aliases
        passport_number title address nationality listed_date remarks
        place_of_birth mother_name father_name date_of_birth organization
        official_gazette decision_number
      ]

      fields = LIVE_HEADERS.map { |h| described_class.normalize_header(h) }

      expect(fields).to eq(expected)
      expect(fields.uniq.size).to eq(LIVE_HEADERS.size)
    end

    it 'is nil-safe' do
      expect(described_class.normalize_header(nil)).to eq(:unknown)
    end
  end

  describe '.from_xlsx' do
    it 'refuses a sheet whose columns collapse onto one field' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı', 'Listeye Alınma Tarihi',
                 'Doğum Tarihi']
      allow(described_class).to receive(:normalize_header)
        .and_return(:reference_number, :name, :listed_date, :listed_date)

      expect { parse(headers, [[1, 'ACME', 'a', 'b']]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /columns collapse onto one field/)
    end

    it 'names both columns in the collapse message' do
      headers = %w[A B]
      allow(described_class).to receive(:normalize_header)
        .and_return(:name, :name)

      expect { parse(headers, [%w[x y]]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError, /"A", "B"/)
    end

    it 'tolerates repeated columns that feed no field' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı', 'Zzz', 'Zzz']

      expect { parse(headers, [[1, 'ACME', 'x', 'y']]) }.not_to raise_error
    end

    it 'keeps both designees when one reference names two of them' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']
      rows = [
        [187, 'DEFENCE INDUSTRIES ORGANISATION (DIO)'],
        [187, 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)']
      ]

      list = parse(headers, rows)

      expect(list.entities.map(&:name)).to eq(rows.map(&:last))
      expect(list.entities.map(&:local_id))
        .to eq(['DEFENCE INDUSTRIES ORGANISATION (DIO)', '187'])
    end

    # The two fixes composed at the sheet. A workbook whose "Sıra No"
    # column carries a decimal display format hands Roo a Float, so the
    # reserved number arrives as 187.0 — and the reservation still has to
    # settle the same pair the same way.
    it 'keeps both designees when the shared reference is a Float' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']
      rows = [
        [187.0, 'DEFENCE INDUSTRIES ORGANISATION (DIO)'],
        [187.0, 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)']
      ]

      list = parse(headers, rows)

      expect(list.entities.map(&:reference_number)).to eq(%w[187 187])
      expect(list.entities.map(&:local_id))
        .to eq(['DEFENCE INDUSTRIES ORGANISATION (DIO)', '187'])
    end

    it 'skips rows carrying no name at all' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']

      list = parse(headers, [[1, 'ACME'], [2, nil]])

      expect(list.entities.map(&:name)).to eq(['ACME'])
    end

    it 'keeps a verbatim repeated row instead of failing the source' do
      # The writer collapses two records that claim one filename with
      # identical content. The gates refuse two records sharing an
      # identifier, so a duplicated row used to fail the whole harvest
      # here and never reach the writer that would have accepted it.
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']
      rows = [[1, 'ACME'], [1, 'ACME']]

      list = parse(headers, rows)

      expect(list.entities.map(&:name)).to eq(['ACME'])
    end

    it 'still refuses two rows that share a number but differ' do
      # Only rows that publish the same record collapse. Collapsing must
      # not become a way for a real collision to pass the gate quietly:
      # two designees under one unreserved number are still a refused
      # harvest.
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']
      rows = [[1, 'ACME'], [1, 'ACME LTD']]

      expect { parse(headers, rows) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier/)
    end

    # Turkey leaves "Sıra No" blank on 37 rows, and the parse has to reach
    # the writer with those rows carrying their own identity rather than
    # 37 copies of one.
    it 'gives every unnumbered row its own identifier' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']
      rows = [[nil, 'DAWOOD AGHA-JANI'], [nil, 'AMIR MOAYYED ALAI'],
              [1, 'ACME']]

      ids = parse(headers, rows).entities.map(&:local_id)

      expect(ids).to eq(['DAWOOD AGHA-JANI', 'AMIR MOAYYED ALAI', '1'])
    end

    it 'reads an integer-formatted reference as its digits' do
      expect(references([1, 'YUN HO-JIN'])).to eq(['1'])
    end

    # The defect this guards. Roo returns a Float for a cell whose display
    # format carries decimals, and "1.0" sanitizes to "10" — the IRI of
    # whoever Turkey numbered 10. Undoing the artefact here keeps the
    # designee on the number Turkey actually published.
    it 'reads a decimal-formatted reference as the same digits' do
      expect(references([1.0, 'YUN HO-JIN'])).to eq(['1'])
    end

    it 'reads either formatting of a number identically' do
      expect(references([1.0, 'A'])).to eq(references([1, 'A']))
    end

    it 'normalizes every whole-number Float on the sheet' do
      rows = [[1.0, 'A'], [10.0, 'B'], [239.0, 'C']]

      expect(references(*rows)).to eq(%w[1 10 239])
    end

    # The collision Copilot reported, pinned in the negative: a sheet
    # carrying both formats must keep the two designees apart.
    it 'keeps a decimal-formatted 1.0 distinct from a plain 10' do
      minted = iris([1.0, 'FIRST DESIGNEE'], [10, 'SECOND DESIGNEE'])

      expect(minted).to eq(['https://www.ammitto.org/entity/tr/1',
                            'https://www.ammitto.org/entity/tr/10'])
      expect(minted.uniq.size).to eq(2)
    end

    it 'mints the same IRI whichever way the sheet was formatted' do
      decimal = iris([1.0, 'A'], [10.0, 'B'], [239.0, 'C'])
      plain   = iris([1, 'A'], [10, 'B'], [239, 'C'])

      expect(decimal).to eq(plain)
    end

    # A fractional value is a different number, not a display artefact, so
    # it is passed through rather than rewritten onto some integer.
    it 'leaves a genuinely fractional reference alone' do
      expect(references([1.5, 'A'])).to eq(['1.5'])
    end

    it 'leaves a non-numeric reference alone' do
      expect(references(['E.47.A.3', 'A'])).to eq(['E.47.A.3'])
    end

    it 'still reads a blank reference as blank' do
      expect(references([nil, 'A'])).to eq([nil])
    end

    # The normalization sits on the cell reader, not on the reference, so
    # any column Turkey reformats the same way is read the same way.
    it 'normalizes a whole-number Float outside the reference column' do
      parsed = parse(NUMERIC_HEADERS, [[1, 'A', 12_345.0]]).entities.first

      expect(parsed.passport_number).to eq('12345')
    end
  end

  describe '.cell_text' do
    it 'keeps an empty cell empty' do
      expect(described_class.cell_text(nil)).to be_nil
    end

    it 'renders a date as an ISO string' do
      expect(described_class.cell_text(Date.new(2021, 2, 24)))
        .to eq('2021-02-24')
    end

    it 'strips surrounding whitespace from text' do
      expect(described_class.cell_text('  TAMAS  ')).to eq('TAMAS')
    end

    { 1.0 => '1', 239.0 => '239', -10.0 => '-10', 0.0 => '0' }
      .each do |float, expected|
        it "renders the whole number #{float} as #{expected.inspect}" do
          expect(described_class.cell_text(float)).to eq(expected)
        end
      end

    it 'keeps a fractional value as written' do
      expect(described_class.cell_text(1.5)).to eq('1.5')
    end

    # Neither equals its own #to_i, and Float::INFINITY#to_i raises, so
    # both have to reach the ordinary string form instead.
    it 'does not raise on a non-finite value' do
      expect(described_class.cell_text(Float::INFINITY)).to eq('Infinity')
      expect(described_class.cell_text(Float::NAN)).to eq('NaN')
    end

    # Past 2**53 consecutive integers share one Float, so a whole-looking
    # value stops being evidence of the integer the workbook held.
    # Rewriting it would assert a precision the value does not carry —
    # and the reader runs on every column, including long passport and
    # registration numbers.
    it 'refuses to invent digits for a Float beyond exact integer range' do
      expect(described_class.cell_text(1.0e20)).to eq('1.0e+20')
    end

    # 2**53 is exactly representable, but so is nothing between it and
    # 2**53 + 2: a cell holding 9007199254740993 rounds onto this same
    # Float, so the Float no longer says which integer was written.
    it 'refuses the first magnitude that stops naming one integer' do
      expect(described_class.cell_text(2.0**53)).to eq('9.007199254740992e+15')
    end

    it 'still normalizes the largest Float that names one integer' do
      expect(described_class.cell_text((2.0**53) - 1))
        .to eq('9007199254740991')
    end

    # Only a Float is a rendering. A text cell is an identifier Turkey
    # wrote, so the sheet reader must hand it back verbatim — leading
    # zeros and all — the way main always did.
    it 'leaves a literal text cell exactly as the workbook wrote it' do
      ['1.0', '1.00', '01.0', '1.5', 'E.47.A.3', '12/A', '1.0e3', '1.']
        .each do |text|
          expect(described_class.cell_text(text)).to eq(text)
        end
    end
  end

  describe '.collapse_duplicate_rows' do
    it 'keeps one copy of a row repeated verbatim' do
      rows = [entity(name: 'A', reference_number: '1'),
              entity(name: 'A', reference_number: '1')]

      expect(described_class.collapse_duplicate_rows(rows).size).to eq(1)
    end

    it 'keeps two rows that differ in a published value' do
      rows = [entity(name: 'A', reference_number: '1'),
              entity(name: 'B', reference_number: '1')]

      expect(described_class.collapse_duplicate_rows(rows).size).to eq(2)
    end

    it 'treats a nil field and an empty one as the same row' do
      # Identity is the published record, and neither of these publishes
      # the field at all — so collapsing them costs the corpus nothing.
      rows = [
        Ammitto::Sources::Tr::SanctionedEntity.new(
          name: 'A', reference_number: '1', remarks: nil
        ),
        Ammitto::Sources::Tr::SanctionedEntity.new(
          name: 'A', reference_number: '1', remarks: ''
        )
      ]

      expect(described_class.collapse_duplicate_rows(rows).size).to eq(1)
    end

    it 'leaves the surviving record untouched' do
      rows = [entity(name: 'A', reference_number: '1'),
              entity(name: 'A', reference_number: '1')]

      expect(described_class.collapse_duplicate_rows(rows).first.name)
        .to eq('A')
    end
  end

  describe '.verify_distinct_local_ids!' do
    it 'accepts records that mint different identifiers' do
      records = [entity(name: 'A', reference_number: '1'),
                 entity(name: 'B', reference_number: '2')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
    end

    it 'refuses two records that would mint one identifier' do
      # "10-" and "-10" both sanitize onto whoever Turkey numbered 10.
      records = [entity(name: 'A', reference_number: '10'),
                 entity(name: 'B', reference_number: '10-')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier.*"A", "B"/m)
    end

    it 'accepts unnumbered records whose names mint different identifiers' do
      records = [entity(name: 'A'), entity(name: 'B')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
    end

    it 'ignores records that carry no identifier' do
      # Neither a reference nor a usable name: nothing to be distinct
      # from, so the gate has no verdict to reach.
      records = [entity(name: '  '), entity(name: '  ')]

      expect(records.map(&:local_id)).to eq([nil, nil])
      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
    end

    # The name fallback opens two collision classes the reference-only
    # gate never saw. Both land here, which is the terminating rule the
    # fallback relies on.
    it 'refuses two unnumbered records whose names slug alike' do
      records = [entity(name: 'ACME (X)'), entity(name: 'ACME  X')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier.*acme-x/m)
    end

    it 'refuses an unnumbered name that slugs onto a published reference' do
      records = [entity(name: 'TR 1'),
                 entity(name: 'B', reference_number: 'TR-1')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier.*"tr-1"/m)
    end

    # Both spellings of one number mint one identifier, so two records
    # carrying them are one collision rather than two records.
    it 'refuses a redundantly spelled number colliding with its plain form' do
      records = [entity(name: 'A', reference_number: '10.0'),
                 entity(name: 'B', reference_number: '10')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier/)
    end

    it 'does not file an unmintable id under the "unknown" fallback' do
      # Utils::IriSanitizer.sanitize answers "unknown" for a reference
      # that slugs to nothing, so grouping on it used to report a
      # collision between a record that mints entity/tr/unknown and one
      # that mints no IRI at all. Only the former owns that id.
      records = [entity(name: 'A', reference_number: '///'),
                 entity(name: 'B', reference_number: 'unknown')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
    end

    it 'still refuses two records that both mint "unknown"' do
      records = [entity(name: 'A', reference_number: 'unknown'),
                 entity(name: 'B', reference_number: 'UNKNOWN')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier/)
    end
  end

  describe '.verify_mintable_local_ids!' do
    it 'refuses a reference that survives sanitization as nothing' do
      # Fetch would write this as "tr----.yaml" and report success; only
      # harmonize would find that it mints no IRI.
      records = [entity(name: 'A', reference_number: '///')]

      expect { described_class.verify_mintable_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        %r{mints no IRI.*"///".*"A"}m)
    end

    it 'accepts a record carrying no reference at all' do
      # Turkey leaves "Sıra No" blank for part of List D. A record that
      # never claimed an identifier is not the same as one whose claim is
      # unusable: it takes its name instead, and this gate has no claim
      # to check.
      records = [entity(name: 'A')]

      expect { described_class.verify_mintable_local_ids!(records) }
        .not_to raise_error
    end

    it 'accepts Turkey\'s own numbering' do
      records = [entity(name: 'A', reference_number: '187'),
                 entity(name: 'B', reference_number: '42')]

      expect { described_class.verify_mintable_local_ids!(records) }
        .not_to raise_error
    end

    it 'refuses a numbered record the reservation left with no id' do
      # The reservation sends this row to its name, and a bare-integer
      # name is refused as an id — so a row Turkey did number resolves to
      # nothing. It used to pass every gate and die at harmonize.
      records = [entity(name: '42', reference_number: '187')]

      expect { described_class.verify_mintable_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /mints no IRI.*reference "187".*"42"/m)
    end

    it 'refuses a numbered record whose name is blank too' do
      records = [entity(name: '  ', reference_number: '187')]

      expect { described_class.verify_mintable_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /reference "187"/)
    end

    it 'refuses a numbered record whose reference is structurally corrupt' do
      # A list in the reference slot mints nothing, so the record has a
      # claim this parse cannot honour — and it is not evidence that
      # Turkey left the cell empty either.
      records = [entity(name: 'A', reference_number: [1])]

      expect { described_class.verify_mintable_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /mints no IRI/)
    end
  end

  describe '.mintable_id' do
    it 'returns the identifier the IRI layer would mint' do
      expect(described_class.mintable_id('187')).to eq('187')
    end

    it 'returns nil for an id that mints no IRI, as for a nil id' do
      # The IRI layer raises for these rather than emitting a shared
      # ".../unknown"; the gate treats them as having no id to collide.
      expect(described_class.mintable_id('///')).to be_nil
      expect(described_class.mintable_id(nil)).to be_nil
    end
  end

  describe '.verify_reservations!' do
    def dtsrc(reference_number: '187')
      entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)',
             reference_number: reference_number)
    end

    def dio(reference_number: '187')
      entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
             reference_number: reference_number)
    end

    # A different designee whose name sanitizes onto the holder's slug.
    # The sanitizer drops every non-ASCII letter, so swapping the "Ç" for
    # another one leaves the slug identical while the name is not.
    def lookalike(reference_number: '187')
      entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ŞENTER (DTSRC)',
             reference_number: reference_number)
    end

    it 'accepts the holder claiming its own reserved reference' do
      expect { described_class.verify_reservations!([dtsrc, dio]) }
        .not_to raise_error
    end

    it 'accepts a delisting: neither the holder nor the reference remains' do
      expect { described_class.verify_reservations!([entity(name: 'A')]) }
        .not_to raise_error
    end

    it 'refuses a payload where the holder was renumbered away' do
      # Nobody may silently inherit entity/tr/187.
      expect { described_class.verify_reservations!([dtsrc(reference_number: '900'), dio]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /now carries reference "900"/)
    end

    it 'refuses a payload where the holder left but the reference persists' do
      expect { described_class.verify_reservations!([dio]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /no row carries the reserved name/)
    end

    it 'refuses a holder that is no longer in the payload but stranded' do
      # The holder was renumbered and nothing claims 187: the published
      # IRI would strand silently.
      expect { described_class.verify_reservations!([dtsrc(reference_number: '900')]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /now carries reference "900"/)
    end

    it 'refuses a reservation that matches more than one row' do
      expect { described_class.verify_reservations!([dtsrc, dtsrc]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /2 rows share the reserved name/)
    end

    it 'lets a third claimant take its own name-derived id' do
      third = entity(name: 'THIRD BODY', reference_number: '187')
      records = [dtsrc, dio, third]

      expect { described_class.verify_reservations!(records) }
        .not_to raise_error
      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
      expect(records.map(&:local_id))
        .to eq(['187', 'DEFENCE INDUSTRIES ORGANISATION (DIO)', 'THIRD BODY'])
    end

    it 'refuses two claimants whose names slug to the same id' do
      # The terminating rule: a name-derived id is not automatically
      # unique either.
      records = [dtsrc,
                 entity(name: 'ACME (X)', reference_number: '187'),
                 entity(name: 'ACME  X', reference_number: '187')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /distinct records mint one identifier/)
    end

    it 'names the published IRI it is protecting' do
      expect { described_class.verify_reservations!([dio]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        %r{entity/tr/187 is published})
    end

    it 'refuses a different designee that sanitizes onto the slug' do
      # Selecting the holder by slug alone would hand entity/tr/187 to
      # this row without a word, because the "Ş" and the "Ç" both vanish.
      expect { described_class.verify_reservations!([lookalike]) }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError,
                        /two different designees share one sanitized name/)
    end

    it 'tolerates the spacing and case Turkey varies freely' do
      spaced = entity(
        name: "  defense technology and science research  ÇENTER (dtsrc) \n",
        reference_number: '187'
      )

      expect { described_class.verify_reservations!([spaced]) }
        .not_to raise_error
    end

    # The gate reads a reference the way identity does, so a record file
    # written before the sheet reader canonicalized anything — where the
    # reserved number is still spelled "187.0" — resolves rather than
    # failing a harvest that is in fact correct.
    it 'recognises a claimant whose number is redundantly spelled' do
      expect do
        described_class.verify_reservations!(
          [dtsrc(reference_number: '187.0'), dio(reference_number: '187.0')]
        )
      end.not_to raise_error
    end

    it 'still refuses the holder renumbered to a genuinely other number' do
      expect do
        described_class.verify_reservations!(
          [dtsrc(reference_number: '1870'), dio]
        )
      end.to raise_error(Ammitto::Sources::Tr::IntegrityError,
                         /now carries reference "1870"/)
    end
  end
end
