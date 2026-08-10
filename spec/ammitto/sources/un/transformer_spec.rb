# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Un::Transformer do
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

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete date.
  describe '#transform_birth_info' do
    def birth_for(**attrs)
      individual = Ammitto::Sources::Un::Individual.new(
        date_of_birth: Ammitto::Sources::Un::IndividualDateOfBirth.new(**attrs)
      )
      transformer.send(:transform_birth_info, individual).first
    end

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
end
