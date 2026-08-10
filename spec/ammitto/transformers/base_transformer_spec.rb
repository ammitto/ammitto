# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Transformers::BaseTransformer do
  let(:transformer) { described_class.new(:test) }

  describe '#source_code' do
    it 'returns the source code' do
      expect(transformer.source_code).to eq(:test)
    end
  end

  describe '#transform' do
    it 'raises NotImplementedError' do
      expect { transformer.transform({}) }.to raise_error(NotImplementedError)
    end
  end

  describe '#generate_entity_id' do
    it 'generates a LIST-AGNOSTIC entity URI (sanitized to lowercase)' do
      id = transformer.send(:generate_entity_id, 'TEST123')
      # Entity IRIs are list-agnostic (no list_type) and sanitized to lowercase
      expect(id).to eq('https://www.ammitto.org/entity/test/test123')
    end
  end

  describe '#generate_entry_id' do
    it 'generates a LIST-SPECIFIC entry URI' do
      id = transformer.send(:generate_entry_id, 'TEST123')
      # Entry IRIs are list-specific and include list_type
      # For unknown source like :test, default_list_type returns nil which becomes 'unknown'
      expect(id).to eq('https://www.ammitto.org/entry/test/unknown/test123')
    end

    it 'allows list_type override' do
      id = transformer.send(:generate_entry_id, 'TEST123', entry_list_type: 'consolidated-list')
      expect(id).to eq('https://www.ammitto.org/entry/test/consolidated-list/test123')
    end
  end

  describe '#authority' do
    it 'returns the authority for the source' do
      auth = transformer.send(:authority)
      expect(auth).to be_nil # :test is not a registered authority
    end
  end

  # The birth-precision invariant: a source-provided year is BirthInfo#year;
  # BirthInfo#date is set only when the source states a complete
  # day-month-year, never padded from a partial expression.
  describe '#create_birth_info' do
    it 'sets date and year for a complete date string' do
      info = transformer.send(:create_birth_info, date: '03 Oct 1988')
      expect(info.date).to eq(Date.new(1988, 10, 3))
      expect(info.year).to eq(1988)
    end

    it 'keeps a bare year as year only, without inventing a date' do
      info = transformer.send(:create_birth_info, date: '1988')
      expect(info.date).to be_nil
      expect(info.year).to eq(1988)
    end

    it 'keeps a month-year string as year only, without inventing a day' do
      info = transformer.send(:create_birth_info, date: 'Oct 1988')
      expect(info.date).to be_nil
      expect(info.year).to eq(1988)
    end

    it 'prefers an explicitly passed year over string extraction' do
      info = transformer.send(:create_birth_info, date: nil, year: 1971)
      expect(info.date).to be_nil
      expect(info.year).to eq(1971)
    end

    it 'passes a caller-resolved Date through unchanged' do
      info = transformer.send(:create_birth_info, date: Date.new(1957, 5, 5))
      expect(info.date).to eq(Date.new(1957, 5, 5))
      expect(info.year).to eq(1957)
    end
  end

  describe '#parse_complete_date' do
    it 'parses a complete ISO date' do
      expect(transformer.send(:parse_complete_date, '1957-05-05'))
        .to eq(Date.new(1957, 5, 5))
    end

    it 'returns nil for a bare year' do
      expect(transformer.send(:parse_complete_date, '1975')).to be_nil
    end

    it 'returns nil for a zero-padded partial date' do
      expect(transformer.send(:parse_complete_date, '1963-00-00')).to be_nil
    end

    it 'returns nil for a month-year string' do
      expect(transformer.send(:parse_complete_date, 'Oct 1988')).to be_nil
    end

    it 'returns nil for an impossible date' do
      expect(transformer.send(:parse_complete_date, '31/02/1990')).to be_nil
    end
  end

  describe '#extract_birth_year' do
    it 'extracts a bare year' do
      expect(transformer.send(:extract_birth_year, '1975')).to eq(1975)
    end

    it 'extracts the year from a circa expression' do
      expect(transformer.send(:extract_birth_year, 'circa 1960')).to eq(1960)
    end

    it 'extracts the year from a zeroed partial date' do
      expect(transformer.send(:extract_birth_year, '00/00/1963')).to eq(1963)
    end

    it 'yields nil for a year range — range handling is a separate concern' do
      expect(transformer.send(:extract_birth_year, '1962 to 1964')).to be_nil
    end

    it 'yields nil for every spelling of a year range' do
      ['1962 to 1964', 'between 1962 and 1964', '1962-1964',
       '1962–1964', 'circa 1962 to 1964'].each do |range|
        expect(transformer.send(:extract_birth_year, range))
          .to(be_nil, "expected #{range.inspect} to name no single year")
      end
    end

    it 'yields nil for non-strings' do
      expect(transformer.send(:extract_birth_year, nil)).to be_nil
      expect(transformer.send(:extract_birth_year, Date.new(1970, 1, 1))).to be_nil
    end
  end

  describe '#multiple_years?' do
    it 'is true only when two different years are named' do
      expect(transformer.send(:multiple_years?, '1962 to 1964')).to be true
      expect(transformer.send(:multiple_years?, '1962-1964')).to be true
      expect(transformer.send(:multiple_years?, 'between 1962 and 1964'))
        .to be true
    end

    it 'is false for one year, however it is written' do
      ['1975', '00/00/1963', '03 Oct 1988', '1963 (1963)']
        .each do |str|
          expect(transformer.send(:multiple_years?, str))
            .to(be(false), "expected #{str.inspect} to name one year")
        end
    end

    # A guard reading "19620101" as 1962 and 0101 would reject a date
    # the parser handles today.
    it 'does not split a run of digits into two years' do
      expect(transformer.send(:multiple_years?, '19620101')).to be false
    end
  end

  describe '#circa_string?' do
    it 'recognizes circa markers' do
      expect(transformer.send(:circa_string?, 'circa 1960')).to be true
      expect(transformer.send(:circa_string?, 'c. 1955')).to be true
      expect(transformer.send(:circa_string?, 'approximately 1965')).to be true
    end

    it 'recognizes the bare "c" marker extract_birth_year strips' do
      expect(transformer.send(:circa_string?, 'c 1955')).to be true
      expect(transformer.send(:circa_string?, 'C 1955')).to be true
    end

    # The year and the circa flag are read from the same string by two
    # different methods; when they disagree the entity claims an exact
    # birth year the source only approximated.
    it 'agrees with extract_birth_year on both "c" spellings' do
      ['c 1955', 'c. 1955'].each do |str|
        expect(transformer.send(:extract_birth_year, str)).to eq(1955)
        expect(transformer.send(:circa_string?, str)).to be true
      end
    end

    it 'rejects plain dates and non-strings' do
      expect(transformer.send(:circa_string?, '03 Oct 1988')).to be false
      expect(transformer.send(:circa_string?, nil)).to be false
    end

    it 'does not read a word starting with c as a circa marker' do
      expect(transformer.send(:circa_string?, 'China 1955')).to be false
      expect(transformer.send(:circa_string?, 'c1955')).to be false
    end
  end
end
