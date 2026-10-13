# frozen_string_literal: true

require 'spec_helper'

module UnTransformerBirthSpecHelpers
  def individual_with(dates, places)
    Ammitto::Sources::Un::Individual.new(
      date_of_birth: dates.map { |d| Ammitto::Sources::Un::IndividualDateOfBirth.new(type_of_date: 'EXACT', date: d) },
      place_of_birth: places.map { |c| Ammitto::Sources::Un::IndividualPlaceOfBirth.new(city: c) }
    )
  end

  def birth_for(**attrs)
    individual = Ammitto::Sources::Un::Individual.new(
      date_of_birth: [Ammitto::Sources::Un::IndividualDateOfBirth.new(**attrs)]
    )
    transformer.send(:transform_birth_info, individual).first
  end
end

RSpec.describe Ammitto::Sources::Un::Transformer do
  include UnTransformerBirthSpecHelpers

  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :un' do
      expect(transformer.source_code).to eq(:un)
    end
  end

  describe '#authority' do
    it 'returns UN authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('un')
      expect(auth.name).to eq('United Nations')
    end
  end

  describe '#transform_birth_info with several births' do
    it 'keeps every date and every place of CDi.011 without pairing them' do
      infos = transformer.send(:transform_birth_info,
                               individual_with(%w[1965-12-28 1965-12-29], %w[Bashali Goma Uvira]))
      expect(infos.size).to eq(5)
      expect(infos.map(&:city).compact).to eq(%w[Bashali Goma Uvira])
      expect(infos.map { |i| i.date&.to_s }.compact).to eq(%w[1965-12-28 1965-12-29])
    end

    it 'keeps the country accessible without pairing several dates with one place' do
      individual = individual_with(%w[1965-12-28 1965-12-29], [])
      individual.place_of_birth = [Ammitto::Sources::Un::IndividualPlaceOfBirth.new(city: 'Goma', country: 'DRC')]
      infos = transformer.send(:transform_birth_info, individual)
      entity = Ammitto::PersonEntity.new(birth_info: infos)

      expect(entity.birth_country).to eq('DRC')
      expected = [
        ['1965-12-28', nil, nil],
        ['1965-12-29', nil, nil],
        [nil, 'Goma', 'DRC']
      ]
      expect(infos.map { |birth| [birth.date&.to_s, birth.city, birth.country] }).to eq(expected)
    end

    it 'still pairs a single date with a single place' do
      infos = transformer.send(:transform_birth_info, individual_with(%w[1965-12-28], %w[Bashali]))
      expect(infos.size).to eq(1)
      expect(infos.first.city).to eq('Bashali')
    end

    it 'marks a place-only entry as not circa' do
      infos = transformer.send(:transform_birth_info, individual_with([], %w[Goma]))
      expect(infos.first.circa).to be(false)
    end

    it 'reads processed YAML written before dates and places were lists' do
      individual = Ammitto::Sources::Un::Individual.from_hash(
        'date_of_birth' => { 'type_of_date' => 'EXACT', 'date' => '1965-12-28' },
        'place_of_birth' => { 'city' => 'Bashali' }
      )
      infos = transformer.send(:transform_birth_info, individual)
      expect(infos.map(&:city)).to eq(['Bashali'])
      expect(infos.map { |i| i.date.to_s }).to eq(['1965-12-28'])
    end

    it 'returns nothing when the record has neither' do
      expect(transformer.send(:transform_birth_info, individual_with([], []))).to eq([])
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete date.
  describe '#transform_birth_info' do
    it 'keeps an EXACT year-only record as year, without inventing January 1' do
      birth = birth_for(type_of_date: 'EXACT', year: 1971)
      expect(birth.year).to eq(1971)
      expect(birth.date).to be_nil
    end

    it 'keeps an APPROXIMATELY year as a circa-flagged year, without a date' do
      birth = birth_for(type_of_date: 'APPROXIMATELY', year: 1960)
      expect(birth.year).to eq(1960)
      expect(birth.date).to be_nil
      expect(birth.circa).to be true
    end

    it 'resolves a complete date to a date plus year' do
      birth = birth_for(type_of_date: 'EXACT', date: '1978-04-28')
      expect(birth.date).to eq(Date.new(1978, 4, 28))
      expect(birth.year).to eq(1978)
    end
  end

  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    let(:entity) { Ammitto::Sources::Un::Entity.new(reference_number: 'QDe.1', listed_on: 'not-a-date') }
    let(:entry_with_unreadable_date) { -> { transformer.send(:create_entry_from_entity, entity) } }

    it_behaves_like 'a parse failure counted once across period dates',
                    source: :un, field: :listed_date, register_field: :listed_on
  end
end
