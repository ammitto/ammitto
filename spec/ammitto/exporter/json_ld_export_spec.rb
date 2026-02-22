# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/exporter/json_ld_export'

RSpec.describe Ammitto::Exporter::JsonLdExport do
  let(:exporter) { described_class.new }

  describe '#build_regime' do
    it 'builds regime from programme code' do
      data = { 'programme' => 'DPRK' }
      regime = exporter.send(:build_regime, data, :eu)

      expect(regime).not_to be_nil
      expect(regime.code).to eq('DPRK')
      expect(regime.name).to eq("Democratic People's Republic of Korea")
    end

    it 'returns nil when no programme' do
      data = {}
      regime = exporter.send(:build_regime, data, :eu)

      expect(regime).to be_nil
    end

    it 'maps Russia/Ukraine regime' do
      data = { 'programme' => 'RUSSIA' }
      regime = exporter.send(:build_regime, data, :eu)

      expect(regime.code).to eq('RUSSIA')
      expect(regime.name).to eq('Russia/Ukraine')
    end
  end

  describe '#build_legal_bases' do
    it 'builds legal bases from regulations array' do
      data = {
        'regulations' => [
          {
            'type' => 'regulation',
            'number_title' => '269/2014 (OJ L85)',
            'publication_date' => '2014-03-17',
            'publication_url' => 'http://eur-lex.europa.eu/test'
          }
        ]
      }

      legal_bases = exporter.send(:build_legal_bases, data, :eu)

      expect(legal_bases.size).to eq(1)
      expect(legal_bases.first.type).to eq('regulation')
      expect(legal_bases.first.identifier).to eq('269/2014 (OJ L85)')
      expect(legal_bases.first.issuance_date.to_s).to eq('2014-03-17')
    end

    it 'returns empty array when no regulations' do
      data = {}
      legal_bases = exporter.send(:build_legal_bases, data, :eu)

      expect(legal_bases).to eq([])
    end

    it 'handles multiple regulations' do
      data = {
        'regulations' => [
          { 'type' => 'regulation', 'number_title' => 'Reg 1' },
          { 'type' => 'decision', 'number_title' => 'Decision 1' }
        ]
      }

      legal_bases = exporter.send(:build_legal_bases, data, :eu)

      expect(legal_bases.size).to eq(2)
      expect(legal_bases.first.type).to eq('regulation')
      expect(legal_bases.last.type).to eq('decision')
    end
  end

  describe '#build_effects' do
    let(:org_entity) do
      Ammitto::OrganizationEntity.new(
        id: 'https://ammitto.org/entity/test',
        entity_type: 'organization',
        names: [Ammitto::NameVariant.new(full_name: 'Test Org', is_primary: true)]
      )
    end

    let(:person_entity) do
      Ammitto::PersonEntity.new(
        id: 'https://ammitto.org/entity/test',
        entity_type: 'person',
        names: [Ammitto::NameVariant.new(full_name: 'Test Person', is_primary: true)]
      )
    end

    it 'builds asset_freeze effect for organizations' do
      data = { 'entity_type' => 'organization' }
      effects = exporter.send(:build_effects, data, org_entity)

      expect(effects.size).to eq(1)
      expect(effects.first.effect_type).to eq('asset_freeze')
      expect(effects.first.scope).to eq('full')
    end

    it 'builds asset_freeze and travel_ban effects for persons' do
      data = { 'entity_type' => 'person' }
      effects = exporter.send(:build_effects, data, person_entity)

      expect(effects.size).to eq(2)
      effect_types = effects.map(&:effect_type)
      expect(effect_types).to contain_exactly('asset_freeze', 'travel_ban')
    end
  end

  describe '#regime_name_for_code' do
    it 'maps known regime codes to names' do
      expect(exporter.send(:regime_name_for_code, 'DPRK', :eu)).to eq("Democratic People's Republic of Korea")
      expect(exporter.send(:regime_name_for_code, 'IRQ', :eu)).to eq('Iraq')
      expect(exporter.send(:regime_name_for_code, 'IRN', :eu)).to eq('Iran')
    end

    it 'returns code as name for unknown codes' do
      expect(exporter.send(:regime_name_for_code, 'UNKNOWN', :eu)).to eq('UNKNOWN')
    end
  end

  describe '#map_instrument_type' do
    it 'maps regulation types' do
      expect(exporter.send(:map_instrument_type, 'regulation')).to eq('regulation')
      expect(exporter.send(:map_instrument_type, 'REGULATION')).to eq('regulation')
    end

    it 'maps decision types' do
      expect(exporter.send(:map_instrument_type, 'decision')).to eq('decision')
    end

    it 'defaults to regulation for unknown types' do
      expect(exporter.send(:map_instrument_type, 'unknown')).to eq('regulation')
      expect(exporter.send(:map_instrument_type, nil)).to eq('regulation')
    end
  end
end
