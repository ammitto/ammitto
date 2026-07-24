# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::SanctionEffect do
  describe '#present?' do
    it 'requires an effect type' do
      expect(described_class.new(effect_type: 'asset_freeze')).to be_present
      expect(described_class.new(scope: 'full')).not_to be_present
    end
  end

  describe '#type_sym and predicates' do
    it 'normalizes spaces and dashes' do
      expect(described_class.new(effect_type: 'asset freeze')).to be_asset_freeze
      expect(described_class.new(effect_type: 'travel-ban')).to be_travel_ban
    end

    it 'is not a freeze or ban for unknown types' do
      effect = described_class.new(effect_type: 'interpretive dance')
      expect(effect.type_sym).to eq(:other)
      expect(effect).not_to be_asset_freeze
      expect(effect).not_to be_travel_ban
    end
  end

  describe 'transformer vocabulary snapshot' do
    it 'normalizes the effect types transformers emitted as of this spec' do
      %w[aircraft_ban arms_embargo asset_freeze debarment entry_ban
         export_ban export_restriction financial_restriction import_ban
         investment_ban sectoral_sanction service_restriction
         technology_restriction trade_restriction transaction_ban
         transport_sanction travel_ban vessel_ban].each do |emitted|
        effect = described_class.new(effect_type: emitted)
        expect(effect.type_sym).to eq(emitted.to_sym),
                                   "#{emitted} collapsed to #{effect.type_sym}"
      end
    end
  end

  describe 'schema-defined vocabulary (self-updating guard)' do
    it 'covers every measure type any announcement schema defines' do
      require 'yaml'
      schema_values = []
      # Structural walk: any enum nested under a measure context's `type`
      # property is measure vocabulary. Measure contexts are the `measures`
      # array properties AND `$defs`-style `measure` definitions referenced
      # via $ref (Japan's schema shape). No sentinel values — each file must
      # yield vocabulary or the per-file assertion below fails loudly.
      collect = lambda do |node, in_measures, in_type, sink|
        case node
        when Hash
          node.each do |key, value|
            if key == 'enum' && value.is_a?(Array) && in_measures && in_type
              sink.concat(value.grep(String))
            else
              collect.call(value, in_measures || %w[measures measure].include?(key),
                           in_type || (in_measures && key == 'type'), sink)
            end
          end
        when Array
          node.each { |item| collect.call(item, in_measures, in_type, sink) }
        end
      end
      schema_files = Dir[File.join(Ammitto.gem_dir, 'schemas', '**',
                                   '*announcement*.{yml,yaml}')]
      expect(schema_files).not_to be_empty, 'no announcement schemas found — path changed?'
      schema_files.each do |file|
        file_values = []
        collect.call(YAML.safe_load_file(file), false, false, file_values)
        expect(file_values).not_to be_empty,
                                   "no measure enum found in #{File.basename(file)} — structure changed?"
        schema_values.concat(file_values)
      end

      uncovered = schema_values.uniq.map(&:to_sym) -
                  Ammitto::Ontology::Types::SANCTION_EFFECT_TYPES
      expect(uncovered).to be_empty,
                           "schema measure types missing from SANCTION_EFFECT_TYPES: #{uncovered.join(', ')}"
    end
  end

  describe '#to_hash' do
    it 'stringifies dates and omits nils' do
      effect = described_class.new(effect_type: 'asset_freeze',
                                   start_date: Date.new(2022, 3, 1))
      expect(effect.to_hash).to eq({ effect_type: 'asset_freeze', start_date: '2022-03-01' })
    end
  end
end
