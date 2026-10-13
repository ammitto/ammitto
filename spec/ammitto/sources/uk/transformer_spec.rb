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
      details = Ammitto::Sources::Uk::IndividualDetails.new(
        individual: Ammitto::Sources::Uk::Individual.new(dobs: [dob])
      )
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
      expect(birth.circa).to be(false)
    end

    it 'preserves a supported circa marker on a complete DOB' do
      birth = birth_for('c. 7 Oct 1988')

      expect(birth.date).to eq(Date.new(1988, 10, 7))
      expect(birth.year).to eq(1988)
      expect(birth.circa).to be(true)
    end

    it 'does not publish marker-like c.Oct as an exact date' do
      birth = birth_for('c.Oct 7 1988')

      expect(birth.date).to be_nil
      expect(birth.year).to be_nil
      expect(birth.circa).to be(false)
    end

    it 'skips dd/mm placeholders entirely' do
      details = Ammitto::Sources::Uk::IndividualDetails.new(
        individual: Ammitto::Sources::Uk::Individual.new(dobs: ['dd/mm/yyyy'])
      )
      expect(transformer.send(:transform_birth_info, details)).to eq([])
    end
  end

  # The fixture holds three real OFSI records: an individual (AFG0006), a
  # ship (DPR0075) and an entity (BEL0164).
  describe '#transform on parsed OFSI records' do
    let(:results) do
      %w[AFG0006 DPR0075 BEL0164].to_h do |id|
        [id, transformer.transform(UkExcerpt.designation(id))]
      end
    end

    it 'publishes the person facts the detail blocks carry' do
      person = results['AFG0006'][:entity]

      expect(person.nationalities).to eq(['Afghanistan'])
      expect(person.title).to eq('Mullah, Haji')
      expect(person.position).to start_with('First Deputy')
      expect(person.birth_info.map(&:country)).to eq(['Afghanistan'])
      expect(person.birth_info.first.city).to include('Pashmul')
    end

    it 'publishes a passport once, however often OFSI repeats it' do
      person = results['AFG0006'][:entity]

      expect(person.identifications.map { |i| [i.type, i.number] })
        .to eq([%w[Passport P04581926]])
      expect(person.identifications.first.note).to include('Kandahar')
    end

    it 'publishes a ship as a vessel with its IMO number' do
      vessel = results['DPR0075'][:entity]

      expect(vessel).to be_a(Ammitto::VesselEntity)
      expect(vessel.imo_number).to eq('9562233')
      expect(vessel.flag_state).to eq('Comoros')
      expect(vessel.previous_flags).to eq(['India'])
      expect(vessel.vessel_type).to eq('Bulk Carrier')
      expect(vessel.build_year).to eq(2011)
    end

    it 'publishes the port entry ban of a ship' do
      effects = results['DPR0075'][:entry].effects

      expect(effects.map(&:effect_type)).to eq(['entry_ban'])
    end

    it 'keeps an entity an organization with its id unchanged' do
      org = results['BEL0164'][:entity]

      expect(org).to be_a(Ammitto::OrganizationEntity)
      expect(org.id).to end_with('bel0164')
    end
  end

  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    let(:designation) { Ammitto::Sources::Uk::Designation.new(unique_id: 'UK1', date_designated: 'not-a-date') }
    let(:entry_with_unreadable_date) { -> { transformer.send(:create_entry, designation) } }

    it_behaves_like 'a parse failure counted once across period dates',
                    source: :uk, field: :listed_date, register_field: :date_designated
  end
end
