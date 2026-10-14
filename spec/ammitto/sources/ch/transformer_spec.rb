# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Sources::Ch::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ch' do
      expect(transformer.source_code).to eq(:ch)
    end
  end

  describe '#authority' do
    it 'returns CH authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ch')
      expect(auth.name).to eq('Switzerland (SECO)')
    end
  end

  describe 'vessel XML through YAML and harmonization' do
    def vessel_target(ssid)
      xml = File.read(File.expand_path("../../../fixtures/ch/target-#{ssid}.xml", __dir__))
      parsed = Ammitto::Sources::Ch::Target.from_xml(xml)
      Ammitto::Sources::Ch::Target.from_yaml(parsed.to_yaml)
    end

    it 'keeps the real Sofos vessel name, IMO and target identifier' do
      target = vessel_target('100001')
      result = transformer.transform(target)

      expect(target.entity_type).to eq('vessel')
      expect(target.full_name).to eq('Sofos')
      expect(result[:entity]).to be_a(Ammitto::VesselEntity)
      expect(result[:entity].entity_type).to eq('vessel')
      expect(result[:entity].names.map(&:full_name)).to eq(['Sofos'])
      expect(result[:entity].imo_number).to eq('9278064')
      expect(result[:entity].id).to eq('https://www.ammitto.org/entity/ch/100001')
      expect(result[:entry].reference_number).to eq('100001')
    end

    it 'preserves Hui Chon and its source alias in exported JSON-LD' do
      target = vessel_target('34461')
      command = Ammitto::Cmd::HarmonizeCommand.new({}, [:ch])
      result = command.send(:transform_data, :ch, YAML.safe_load(target.to_yaml))
      entity = result[:entity]

      expect(entity['entityType']).to eq('vessel')
      expect(entity['imoNumber']).to eq('8405270')
      expect(entity['names'].map { |name| name['fullName'] }).to eq(['Hui Chon', 'Hwang Gum San 2'])
      expect(entity['names'].map { |name| name['isPrimary'] }).to eq([true, false])
    end

    it 'routes an object wrapper without a sanctions-set ID as a target' do
      data = YAML.safe_load(vessel_target('34461').to_yaml)
      data.delete('sanctions_set_id')
      command = Ammitto::Cmd::HarmonizeCommand.new({}, [:ch])

      expect(command.send(:transform_data, :ch, data)[:entity]['entityType']).to eq('vessel')
    end

    it 'does not invent an IMO when the source does not supply one' do
      target = vessel_target('100001')
      target.object.other_information = nil

      expect(transformer.transform(target)[:entity].imo_number).to be_nil
    end

    it 'refuses an unsupported object instead of silently making an organization' do
      target = vessel_target('100001')
      target.object.object_type = 'aircraft'

      expect { transformer.transform(target) }.to raise_error(/Unsupported CH object type/)
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete day-month-year.
  describe '#transform_birth_info' do
    def birth_for(day: nil, month: nil, year: nil)
      identity = Ammitto::Sources::Ch::Identity.new(
        ssid: '100',
        day_month_year: Ammitto::Sources::Ch::DayMonthYear.new(
          day: day, month: month, year: year
        )
      )
      transformer.send(:transform_birth_info, identity).first
    end

    it 'keeps a year-only record as year, without a date' do
      birth = birth_for(year: 1975)
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'keeps a year-month record as year, without inventing a day' do
      birth = birth_for(year: 1975, month: 3)
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'resolves a fully stated record to a date plus year' do
      birth = birth_for(year: 1975, month: 3, day: 5)
      expect(birth.date).to eq(Date.new(1975, 3, 5))
      expect(birth.year).to eq(1975)
    end
  end
end
