# frozen_string_literal: true

require 'ammitto/sources/tr'

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

  def parse(headers, rows)
    sheet = sheet_for(headers, rows)
    allow(Roo::Excelx).to receive(:new)
      .and_return(instance_double(Roo::Excelx, sheet: sheet))

    described_class.from_xlsx('ignored.xlsx')
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

    it 'maps every live column to a distinct field' do
      fields = LIVE_HEADERS.map { |h| described_class.normalize_header(h) }

      expect(fields.tally.select { |_f, n| n > 1 }).to be_empty
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

    it 'skips rows carrying no name at all' do
      headers = ['Sıra No', 'Gerçek Kişi Soyadı Ünvanı']

      list = parse(headers, [[1, 'ACME'], [2, nil]])

      expect(list.entities.map(&:name)).to eq(['ACME'])
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

    it 'ignores records that carry no identifier' do
      records = [entity(name: 'A'), entity(name: 'B')]

      expect { described_class.verify_distinct_local_ids!(records) }
        .not_to raise_error
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
  end
end
