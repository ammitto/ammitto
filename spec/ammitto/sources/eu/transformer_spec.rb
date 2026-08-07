# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Eu::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :eu' do
      expect(transformer.source_code).to eq(:eu)
    end
  end

  describe '#authority' do
    it 'returns EU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('eu')
      expect(auth.name).to eq('European Union')
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete birthdate.
  describe '#transform_birthdates' do
    def birth_for(**attrs)
      birthdate = Ammitto::Sources::Eu::Birthdate.new(**attrs)
      transformer.send(:transform_birthdates, [birthdate]).first
    end

    it 'keeps a year-only record as year, without inventing January 1' do
      birth = birth_for(year: 1962)
      expect(birth.year).to eq(1962)
      expect(birth.date).to be_nil
    end

    it 'keeps a year-month record as year, without inventing a date' do
      birth = birth_for(year: 1962, month_of_year: 9)
      expect(birth.year).to eq(1962)
      expect(birth.date).to be_nil
    end

    it 'resolves a complete birthdate to a date plus year' do
      birth = birth_for(birthdate: '1962-09-03', year: 1962)
      expect(birth.date).to eq(Date.new(1962, 9, 3))
      expect(birth.year).to eq(1962)
    end

    it 'preserves the circa flag' do
      birth = birth_for(year: 1962, circa: true)
      expect(birth.circa).to be true
      expect(birth.date).to be_nil
    end
  end
end
