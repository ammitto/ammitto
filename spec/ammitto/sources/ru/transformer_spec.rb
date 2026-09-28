# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ru::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ru' do
      expect(transformer.source_code).to eq(:ru)
    end
  end

  describe '#authority' do
    it 'returns RU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ru')
      expect(auth.name).to eq('Russia (MID/CBR)')
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete day-month-year.
  describe '#transform birth info' do
    def birth_for(dob_string)
      entity = Ammitto::Sources::Ru::SanctionedEntity.new(
        english_name: 'Test Person',
        entity_type: 'person',
        date_of_birth: dob_string
      )
      transformer.transform(entity)[:entity].birth_info.first
    end

    it 'keeps a year-only DOB as year, without a date' do
      birth = birth_for('1975')
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
      expect(birth.circa).to be(false)
    end

    it 'marks c.1955 as circa while keeping its year' do
      birth = birth_for('c.1955')

      expect(birth.year).to eq(1955)
      expect(birth.date).to be_nil
      expect(birth.circa).to be(true)
    end

    it 'resolves a complete DOB to a date plus year' do
      birth = birth_for('1975-02-01')
      expect(birth.date).to eq(Date.new(1975, 2, 1))
      expect(birth.year).to eq(1975)
      expect(birth.circa).to be(false)
    end
  end

  # An unreadable announcement_date publishes as nil in every mode;
  # visibility only adds the report.
  describe 'parse failure visibility for announcement_date' do
    include_context 'with parse failure log capture'

    let(:entity) do
      Ammitto::Sources::Ru::SanctionedEntity.new(
        english_name: 'Test Org',
        entity_type: 'organization',
        list_type: 'stop_list',
        source_url: 'https://mid.ru/example',
        announcement_date: 'not-a-date'
      )
    end

    it 'warns and counts, still publishing nil' do
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = transformer.transform(entity)
      end

      expect(result[:entry].announcement.publish_date).to be_nil
      expect(io.string).to include('Parse failure in ru.announcement_date')
      expect(run.count(:ru)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = transformer.transform(entity)
      end

      expect(result[:entry].announcement.publish_date).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:ru)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { transformer.send(:parse_announcement_date, 'not-a-date') }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:ru)
          expect(e.field).to eq(:announcement_date)
        }
    end
  end
end
