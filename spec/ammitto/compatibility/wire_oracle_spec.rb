# frozen_string_literal: true

require 'spec_helper'
require 'date'
require 'json'
require 'yaml'

# Wire output of both facades against what the base commit emitted.
#
# base_model_inventory.json holds, per class, the JSON, YAML and to_hash
# of an instance with every base attribute set. The legacy flat facade must
# still emit exactly that. The canonical side may only gain keys it used to
# drop silently: NameVariant is_strong and the entities' linked_entities.
#
# value_object_baseline.json is root's independent 32-case capture of the
# eight canonical value objects (missing / explicit nil / complete / false
# flags). It must still hold, with the is_strong omission corrected.
RSpec.describe 'Compatibility wire oracle' do
  fixtures = File.expand_path('../../fixtures/compatibility', __dir__)
  inventory = JSON.parse(File.read(File.join(fixtures, 'base_model_inventory.json'))).fetch('concepts')
  baseline = JSON.parse(File.read(File.join(fixtures, 'value_object_baseline.json')))
  base_attributes = inventory.values.flat_map(&:values).to_h do |side|
    [side.fetch('class'), side.fetch('attributes').keys]
  end

  # Mirrors the capture script: one sentinel per base attribute; a nested
  # model past depth 2 leaves its attribute out entirely
  sentinel = lambda do |klass, depth = 0|
    names = base_attributes.fetch(klass.name) { klass.attributes.keys.map(&:to_s) }
    attributes = names.to_h do |name|
      attribute = klass.attributes.fetch(name.to_sym)
      type = attribute.type
      nested = type.is_a?(Class) && type <= Lutaml::Model::Serializable
      next [name.to_sym, nil] if nested && depth > 2

      value =
        if nested
          sentinel.call(type, depth + 1)
        else
          { 'String' => "sentinel_#{name}", 'Date' => Date.new(2024, 2, 29), 'Integer' => 1985,
            'Float' => 12.5, 'Boolean' => true,
            'Hash' => { 'sentinel_key' => "sentinel_#{name}" } }.fetch(type.name.split('::').last)
        end
      [name.to_sym, attribute.collection? ? [value] : value]
    end
    klass.new(attributes.compact)
  end

  wire = lambda do |object|
    { 'json' => JSON.parse(object.to_json),
      'yaml' => YAML.safe_load(object.to_yaml, permitted_classes: [Date, Time, Symbol]),
      'hash' => JSON.parse(JSON.generate(object.to_hash)) }
  end

  # Removes keys the base output lacked, only when they are listed corrections
  prune = lambda do |current, base, allowed, removed = []|
    case current
    when Hash
      kept = current.reject do |key, _|
        extra = base.is_a?(Hash) && !base.key?(key) && allowed.include?(key)
        removed << key if extra
        extra
      end
      [kept.to_h { |key, value| [key, prune.call(value, base.is_a?(Hash) ? base[key] : nil, allowed, removed).first] },
       removed]
    when Array
      [current.each_with_index.map { |value, index| prune.call(value, base.is_a?(Array) ? base[index] : nil, allowed, removed).first },
       removed]
    else [current, removed]
    end
  end

  # The base dropped NameVariant is_strong from JSON, YAML and to_hash, also
  # inside the entities that carry names
  corrected = { 'NameVariant' => %w[is_strong], 'PersonEntity' => %w[is_strong],
                'OrganizationEntity' => %w[is_strong] }

  inventory.each do |name, sides|
    describe name do
      it 'legacy flat facade still emits the base JSON, YAML and to_hash values' do
        flat = sentinel.call(Object.const_get(sides.fetch('flat').fetch('class')))
        expect(wire.call(flat)).to eq(sides.fetch('flat').fetch('sentinel_wire'))
      end

      next unless sides.key?('ontology')

      it 'canonical class emits the base output plus only the listed corrections' do
        canonical = sentinel.call(Object.const_get(sides.fetch('ontology').fetch('class')))
        current = wire.call(canonical)
        base = sides.fetch('ontology').fetch('sentinel_wire')
        pruned, removed = prune.call(current, base, corrected.fetch(name, []))

        expect(pruned).to eq(base)
        # Each correction must actually be present, not merely tolerated
        expect(removed.uniq).to match_array(corrected.fetch(name, []))
      end
    end
  end

  describe 'root 32-case value object baseline' do
    baseline.each do |name, cases|
      klass = Ammitto::Ontology::ValueObjects.const_get(name)
      fields = cases.fetch('missing').fetch('fields').keys

      inputs = {
        'missing' => {},
        'explicit_nil' => fields.to_h { |key| [key.to_sym, nil] },
        'complete' => fields.to_h do |key|
          type = klass.attributes.fetch(key.to_sym).type.name.split('::').last
          [key.to_sym, { 'String' => "sentinel_#{key}", 'Date' => Date.new(2024, 2, 29), 'Boolean' => true,
                         'Integer' => 1985 }.fetch(type)]
        end,
        'false_flags' => fields.select { |key| klass.attributes.fetch(key.to_sym).type.name.end_with?('Boolean') }
                               .to_h { |key| [key.to_sym, false] }
      }

      inputs.each do |label, input|
        it "#{name} #{label} matches the captured fields, flags and wire output" do
          object = klass.new(input)
          expected = Marshal.load(Marshal.dump(cases.fetch(label)))
          strong = expected.dig('fields', 'is_strong')
          unless strong.nil?
            # The base dropped is_strong from every output; corrected here
            %w[json yaml hash neo4j].each { |format| expected[format]['is_strong'] = strong }
          end

          actual = {
            'fields' => JSON.parse(JSON.generate(fields.to_h { |key| [key, object.public_send(key)] })),
            'default_flags' => fields.to_h { |key| [key, object.using_default?(key.to_sym)] },
            'json' => JSON.parse(object.to_json),
            'yaml' => YAML.safe_load(object.to_yaml, permitted_classes: [Date, Time]),
            'hash' => JSON.parse(JSON.generate(object.to_hash))
          }
          if object.respond_to?(:to_neo4j_properties)
            actual['neo4j'] = JSON.parse(JSON.generate(object.to_neo4j_properties))
            actual['neo4j_labels'] = klass.all_neo4j_labels
          end
          expect(actual).to eq(expected)
        end
      end
    end
  end
end
