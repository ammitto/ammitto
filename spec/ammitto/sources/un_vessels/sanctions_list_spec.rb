# frozen_string_literal: true

require 'spec_helper'
require 'pdf-reader'
require 'ammitto'
require 'ammitto/sources/un_vessels'

RSpec.describe Ammitto::Sources::UnVessels::SanctionsList do
  # Verbatim excerpt of the 1718 Committee PDF text exactly as
  # PDF::Reader hands it back (list retrieved 2026-08-06): the table
  # header, a single-name row, a multi-name row, an MMSI continuation
  # line (nine digits, also "1:"-prefixed), the one row whose IMO cell
  # reads "Does not exist", and narrative lines. Driving .from_text
  # with these strings rather than a committed PDF fixture follows the
  # TR spec's convention of testing at the seam the extraction library
  # hands back.
  let(:excerpt) do
    <<~TEXT
      #                    Vessel Name                    IMO number      designation   1718 (2006)   2321        2321         and           operated by
           1: AN SAN 1                                    7303803         30-Mar-18     na            na          Yes          Yes           na
           Other        DPRK tanker M/V AN SAN 1 was
          1: Blue Nouvelle 2: Greenlight 3: Chong Bong    8909575         21-Jun-17    na           na           na          na             Yes
                                                            1: 514569000
           1: MIN NING DE YOU 078                          Does not exist 30-Mar-18    na           Yes          na           Yes           na
           information                                      1: 445539000
    TEXT
  end

  let(:list) { described_class.from_text(excerpt) }

  describe '.from_text' do
    it 'parses every vessel row and nothing else' do
      expect(list.vessels.map(&:vessel_name))
        .to eq(['AN SAN 1', 'Blue Nouvelle', 'MIN NING DE YOU 078'])
    end

    it 'reads the identity columns of a single-name row' do
      an_san = list.vessels.first

      expect(an_san.imo_number).to eq('7303803')
      expect(an_san.designation_date).to eq(Date.new(2018, 3, 30))
      expect(an_san.id).to eq('un-vessel-7303803')
      expect(an_san.entity_type).to eq('vessel')
    end

    it 'splits a numbered name cell into variants, first name primary' do
      names = list.vessels[1].names

      expect(names.map(&:full_name))
        .to eq(['Blue Nouvelle', 'Greenlight', 'Chong Bong'])
      expect(names.map(&:is_primary)).to eq([true, false, false])
    end

    it 'keeps the vessel listed without an IMO under a stable name slug' do
      vessel = list.vessels.last

      expect(vessel.imo_number).to be_nil
      expect(vessel.local_id).to eq('min-ning-de-you-078')
      expect(vessel.id).to eq('un-vessel-min-ning-de-you-078')
    end

    it 'stamps list provenance' do
      expect(list.source).to eq('un_vessels')
      expect(list.fetched_at).not_to be_nil
    end
  end

  describe 'structural integrity of the parsed set' do
    # The committee reformats this PDF rather than versioning it, and
    # VESSEL_ROW is anchored to the current layout. A layout change
    # makes the regexp go quiet rather than wrong — so a zero-row
    # parse must fail the harvest, never yield a green empty list.
    it 'refuses text in which no vessel row matches' do
      narrative = <<~TEXT
        #                    Vessel Name                    IMO number
             Other        DPRK tanker M/V AN SAN 1 was
      TEXT

      expect { described_class.from_text(narrative) }
        .to raise_error(described_class::IntegrityError,
                        /no vessel row matched/)
    end

    it 'refuses rows that collapse onto one id' do
      duplicated = <<~TEXT
        1: AN SAN 1                                    7303803         30-Mar-18     na
        1: AN SAN 2                                    7303803         30-Mar-18     na
      TEXT

      expect { described_class.from_text(duplicated) }
        .to raise_error(described_class::IntegrityError,
                        /collapse onto one id.*7303803/)
    end

    it 'refuses a set in which no row carries an IMO number' do
      imo_less = <<~TEXT
        1: MIN NING DE YOU 078                          Does not exist 30-Mar-18    na
      TEXT

      expect { described_class.from_text(imo_less) }
        .to raise_error(described_class::IntegrityError,
                        /no parsed row carries an IMO number/)
    end
  end

  describe '.from_pdf' do
    it 'parses the text PDF::Reader extracts from the document' do
      page = instance_double(PDF::Reader::Page, text: excerpt)
      reader = instance_double(PDF::Reader, pages: [page])
      allow(PDF::Reader).to receive(:new)
        .with('vessels.pdf').and_return(reader)

      expect(described_class.from_pdf('vessels.pdf').count).to eq(3)
    end
  end

  describe 'round trip through the fetched YAML shape' do
    # fetch writes each vessel with Lutaml #to_yaml; harmonize reads
    # the file back with YAML.safe_load_file and Vessel.from_hash.
    it 'preserves names, IMO and date across write and re-read' do
      data = YAML.safe_load(list.vessels[1].to_yaml,
                            permitted_classes: [Date, Time])
      restored = Ammitto::Sources::UnVessels::Vessel.from_hash(data)

      expect(restored.vessel_name).to eq('Blue Nouvelle')
      expect(restored.previous_names).to eq(['Greenlight', 'Chong Bong'])
      expect(restored.imo_number).to eq('8909575')
      expect(restored.designation_date).to eq(Date.new(2017, 6, 21))
    end
  end

  describe 'harmonization of the vessel without an IMO number' do
    it 'mints entity and entry IRIs from the name slug' do
      result = Ammitto::Sources::UnVessels::Transformer.new
                                                       .transform(list.vessels.last)

      expect(result[:entity].id)
        .to include('/entity/un_vessels/min-ning-de-you-078')
      expect(result[:entry].id).to include('min-ning-de-you-078')
      expect(result[:entry].id).not_to include('/unknown')
    end
  end
end
