# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'

RSpec.describe Ammitto::Sources::Cn::Entity do
  describe '#list_type_code' do
    def code_for(value)
      described_class.new(sanction_list: value).list_type_code
    end

    it 'matches the Chinese labels from the schema enum' do
      expect(code_for('反制裁清单')).to eq('anti_sanctions')
      expect(code_for('不可靠实体清单')).to eq('unreliable_entity')
      expect(code_for('出口管制管控名单')).to eq('export_control')
    end

    it 'matches the source-prefixed slugs the data stores' do
      expect(code_for('cn/anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('cn/unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('cn/import-export-control-list')).to eq('export_control')
    end

    it 'matches bare slugs without the source prefix' do
      expect(code_for('anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('import-export-control-list')).to eq('export_control')
    end

    it 'ignores surrounding whitespace' do
      expect(code_for(" cn/anti-sanction-list\n")).to eq('anti_sanctions')
    end

    it 'returns unknown for unrecognized, empty, and nil values' do
      expect(code_for('no-such-list')).to eq('unknown')
      expect(code_for('')).to eq('unknown')
      expect(code_for(nil)).to eq('unknown')
    end
  end
end
