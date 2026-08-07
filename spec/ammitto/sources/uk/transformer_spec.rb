# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Uk::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :uk' do
      expect(transformer.source_code).to eq(:uk)
    end
  end

  describe '#authority' do
    it 'returns UK authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('uk')
      expect(auth.name).to eq('United Kingdom (OFSI)')
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete day-month-year. OFSI writes unknown components as zeros
  # ("00/00/1975"), which the model normalizes to "1975-00-00".
  describe '#transform_birth_info' do
    def birth_for(dob)
      details = Ammitto::Sources::Uk::IndividualDetails.new(dobs: [dob])
      transformer.send(:transform_birth_info, details).first
    end

    it 'keeps a zeroed partial DOB as year, without a date' do
      birth = birth_for('00/00/1975')
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'keeps a zeroed day-month with known month as year, without a date' do
      birth = birth_for('00/03/1975')
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'resolves a complete DD/MM/YYYY DOB to a date plus year' do
      birth = birth_for('07/05/1963')
      expect(birth.date).to eq(Date.new(1963, 5, 7))
      expect(birth.year).to eq(1963)
    end

    it 'skips dd/mm placeholders entirely' do
      details = Ammitto::Sources::Uk::IndividualDetails.new(dobs: ['dd/mm/yyyy'])
      expect(transformer.send(:transform_birth_info, details)).to eq([])
    end
  end
end
