# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/tr/sanctions_list'
require 'ammitto/sources/tr/transformer'

RSpec.describe Ammitto::Sources::Tr::SanctionsList do
  # Turkey's own column titles, so normalize_header maps them the way a
  # real sheet does rather than the way a fixture wishes it would.
  HEADER_ROW = ['Sıra No', 'Gerçek Kişi Adı Soyadı', 'Pasaport No'].freeze

  # Drives the real .from_xlsx. Roo is stubbed rather than a workbook
  # written to disk, because the whole point is what Roo HANDS BACK for a
  # numeric cell — Integer or Float according to the cell's display
  # format — and that is exactly the seam a fixture file would hide.
  def parse(*rows)
    sheet = instance_double(Roo::Excelx::Sheet)
    allow(sheet).to receive(:last_row).and_return(rows.size + 1)
    allow(sheet).to receive(:row) do |number|
      number == 1 ? HEADER_ROW : rows[number - 2]
    end
    workbook = instance_double(Roo::Excelx)
    allow(workbook).to receive(:sheet).with(0).and_return(sheet)
    allow(Roo::Excelx).to receive(:new).and_return(workbook)

    described_class.from_xlsx('ignored.xlsx')
  end

  def references(*rows)
    parse(*rows).entities.map(&:reference_number)
  end

  def iris(*rows)
    transformer = Ammitto::Sources::Tr::Transformer.new
    parse(*rows).entities.map { |e| transformer.transform(e)[:entity].id }
  end

  describe '.from_xlsx' do
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
      parsed = parse([1, 'A', 12_345.0]).entities.first

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
end
