# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/us/sdn_entry'

RSpec.describe Ammitto::Sources::Us::SdnEntry do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is uid when present' do
      expect(described_class.new(uid: '12345').identifier).to eq('12345')
    end

    it 'is nil when uid is blank' do
      expect(described_class.new(uid: nil).identifier).to be_nil
    end
  end

  describe 'parsing the OFAC export' do
    include_context 'with OFAC SDN excerpt'

    let(:entries) { Ammitto::Sources::Us::SdnList.from_xml(fixture).entries.to_h { |e| [e.uid, e] } }

    it 'reads nationalityList, which holds <nationality> children' do
      expect(entries['7006'].nationalities).to eq(['Somalia'])
      expect(entries['6946'].nationalities).to eq(%w[Tunisia Ireland])
    end

    it 'reads citizenshipList' do
      expect(entries['7006'].citizenships).to eq(['Somalia'])
      expect(entries['6924'].citizenships).to eq(%w[Egypt Kenya])
    end

    it 'reads every vesselInfo child' do
      info = entries['4243'].vessel_info
      expect(info.vessel_type).to eq('General Cargo')
      expect(info.vessel_flag).to eq('Panama')
      expect(info.tonnage).to eq('2595')
      expect(info.gross_registered_tonnage).to eq('1865')
    end

    it 'reads the call sign and owner' do
      info = entries['4238'].vessel_info
      expect(info.call_sign).to eq('CL2192')
      expect(info.vessel_owner).to eq('Samir de Navegacion S.A.')
    end

    it 'keeps the new fields through the processed YAML round trip' do
      restored = described_class.from_yaml(entries['4243'].to_yaml)
      expect(restored.vessel_info.vessel_flag).to eq('Panama')

      restored = described_class.from_yaml(entries['6946'].to_yaml)
      expect(restored.nationalities).to eq(%w[Tunisia Ireland])
    end

    it 'leaves the lists empty when the source has none' do
      expect(entries['4243'].nationalities).to eq([])
      expect(entries['7006'].vessel_info).to be_nil
    end
  end
end
