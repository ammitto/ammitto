# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ru::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ru' do
      expect(transformer.source_code).to eq(:ru)
    end
  end

  # Ammitto 1.0.0 returned one result per entity for a flat announcement;
  # the announcement-file contract must not replace that for released
  # callers.
  describe '#transform_announcement with a flat ListAnnouncement' do
    it 'returns one entity/entry pair per entity, as in 1.0.0' do
      flat = Ammitto::Sources::Ru::ListAnnouncement.from_parsed_data(
        number: '1', list_type: 'stop_list',
        entities: [{ russian_name: 'Иванов', english_name: 'Ivanov' }]
      )

      results = transformer.transform_announcement(flat)

      expect(results.map(&:keys)).to eq([%i[entity entry]])
      expect(results.first[:entity]).to be_a(Ammitto::PersonEntity)
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
end
