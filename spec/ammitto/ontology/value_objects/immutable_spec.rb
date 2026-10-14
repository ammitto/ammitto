# frozen_string_literal: true

require 'spec_helper'
require 'date'
require 'json'
require 'stringio'
require 'tempfile'

RSpec.describe 'Immutable ontology value objects' do
  include IsolatedLoadHelper

  def sample_attributes(klass)
    klass.attributes.to_h do |name, attribute|
      value = case attribute.type.name.split('::').last
              when 'String' then "original #{name}"
              when 'Date' then Date.new(1964, 2, 29)
              when 'Boolean' then false
              when 'Integer' then 1964
              end
      [name, value]
    end
  end

  %w[NameVariant Address Identification BirthInfo LegalInstrument SanctionEffect TemporalPeriod ContactInfo].each do |name|
    context name do
      let(:klass) { Ammitto::Ontology::ValueObjects.const_get(name) }
      let(:attributes) { sample_attributes(klass) }

      it 'loads independently and returns a sealed canonical object' do
        file = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        code = "klass = Ammitto::Ontology::ValueObjects::#{name}; value = klass.new; abort 'unsealed' unless value.frozen? && value.instance_of?(klass)"
        ok, error = load_in_subprocess("ammitto/ontology/value_objects/#{file}", code)
        expect(ok).to be(true), error
      end

      it 'owns and freezes its strings and dates while leaving caller values mutable' do
        value = klass.new(attributes)
        expect(value).to be_frozen
        attributes.each do |key, original|
          next unless original.is_a?(String) || original.is_a?(Date)

          expect(value.public_send(key)).to be_frozen
          expect(value.public_send(key)).not_to equal(original)
          expect(original).not_to be_frozen
        end
      end

      it 'rejects ordinary and builder-style setters after construction' do
        value = klass.new(attributes)
        key = attributes.keys.first
        expect { value.public_send("#{key}=", attributes[key]) }.to raise_error(FrozenError)
        expect { value.public_send(key, attributes[key]) }.to raise_error(FrozenError)
      end

      it 'finishes both builder forms before sealing and seals copied objects' do
        key = attributes.keys.first
        attribute_value = attributes[key]
        explicit = klass.new { |value| value.public_send("#{key}=", attribute_value) }
        receiverless = klass.new { public_send(key, attribute_value) }
        [explicit, receiverless, explicit.dup, explicit.clone, explicit.clone(freeze: false)].each do |value|
          expect(value).to be_frozen
          expect(value.public_send(key)).to eq(attributes[key])
        end
      end

      %w[json yaml].each do |format|
        it "seals #{format} hydration, arrays and real typed child mappings" do
          value = klass.new(attributes)
          parsed = klass.public_send("from_#{format}", value.public_send("to_#{format}"))
          expect(parsed).to be_frozen
          expect(parsed.class).to eq(klass)
          klass.attributes.each_key { |key| expect(parsed.public_send(key)).to eq(value.public_send(key)) }

          value_class = klass
          envelope = Class.new(Lutaml::Model::Serializable) do
            attribute :values, value_class, collection: true
            key_value { map :values, to: :values }
          end
          container = envelope.new(values: [value])
          hydrated = envelope.public_send("from_#{format}", container.public_send("to_#{format}"))
          expect(hydrated).not_to be_frozen
          expect(hydrated.values.first).to be_frozen
          expect(klass.from_json('[{},{}]')).to all(be_frozen)
        end
      end

      it 'hydrates of/blank mappings and replaces an instance without changing its caller' do
        value = klass.new(attributes)
        original = value.to_json
        expect(klass.of_json(JSON.parse(original))).to be_frozen
        expect(klass.apply_mappings({}, :json)).to be_frozen
        result = klass.apply_mappings(JSON.parse(original), :json, instance: value)
        expect(result).to be_frozen
        expect(result).not_to equal(value)
        expect(value.to_json).to eq(original)
      end

      it 'preserves missing/default metadata and marks only replacement keys explicit' do
        value_class = klass
        mutable = Class.new(Lutaml::Model::Serializable) { import_model(value_class) }
        baseline = mutable.from_json('{}')
        value = klass.from_json('{}')
        # NameVariant's existing script normalization intentionally has no
        # generated default flag; the data model must share that definition.
        klass.attributes.each_key do |key|
          expected = name == 'NameVariant' && key == :script ? nil : baseline.using_default?(key)
          expect(value.using_default?(key)).to eq(expected)
        end
        replacement_key = klass.attributes.keys.first
        replacement = value.with(**{ replacement_key => attributes[replacement_key] })
        expect(replacement).to be_frozen
        expect(replacement.using_default?(replacement_key)).to be false
        (klass.attributes.keys - [replacement_key]).each do |key|
          expect(replacement.using_default?(key)).to eq(value.using_default?(key))
        end
      end

      it 'keeps raw allocation and mutable hydration factories private' do
        %i[allocate allocate_for_deserialization hydration_model].each do |factory|
          expect { klass.public_send(factory) }.to raise_error(NoMethodError)
        end
      end

      it 'preserves Hash default semantics in mapping bookkeeping' do
        mutable = klass.send(:hydration_model).send(:allocate_for_deserialization)
        key = attributes.keys.first
        mutable.public_send("#{key}=", attributes[key])
        value = klass.apply_mappings({}, :json, instance: mutable)
        expect(value.using_default?(key)).to be false
        (klass.attributes.keys - [key]).each do |other|
          expect(value.using_default?(other)).to eq(mutable.using_default?(other))
        end
        expect(value.instance_variable_get(:@using_default).default).to be true
      end

      it 'never exposes a mutable canonical value from an interrupted builder' do
        captured = nil
        expect do
          klass.new do |building|
            captured = building
            raise 'Interrupted construction'
          end
        end.to raise_error(RuntimeError, 'Interrupted construction')
        expect(captured).not_to be_a(klass)
      end

      it 'restores sealed Marshal values with fields and default metadata intact' do
        [klass.new, klass.new(attributes.transform_values { nil }), klass.new(attributes), klass.from_json('{}')].each do |value|
          restored = Marshal.load(Marshal.dump(value))
          expect(restored).to be_an_instance_of(klass)
          expect(restored).to be_frozen
          klass.attributes.each_key do |key|
            expect(restored.public_send(key)).to eq(value.public_send(key))
            expect(restored.using_default?(key)).to eq(value.using_default?(key))
            field = restored.public_send(key)
            expect(field).to be_frozen if field.is_a?(String) || field.is_a?(Date)
          end
          expect(restored.to_json).to eq(value.to_json)
          expect(restored.to_yaml).to eq(value.to_yaml)
          expect(restored.to_hash).to eq(value.to_hash)
          expect(restored.lutaml_register).to eq(value.lutaml_register)
          flags = restored.instance_variable_get(:@using_default)
          original_flags = value.instance_variable_get(:@using_default)
          expect(flags.keys).to eq(original_flags.keys)
          expect(flags.default).to eq(original_flags.default)
          expect(flags).to be_frozen
          if value.respond_to?(:to_neo4j_properties)
            expect(restored.to_neo4j_properties).to eq(value.to_neo4j_properties)
            expect(restored.neo4j_labels).to eq(value.neo4j_labels)
          end
          key = attributes.keys.first
          expect { restored.public_send("#{key}=", attributes[key]) }.to raise_error(FrozenError)
        end
      end

      it 'borrows native YAML IO input and owns the parsed result' do
        value = klass.new(attributes)
        input = StringIO.new(value.to_yaml)
        parsed = klass.from_yaml(input)
        expect(parsed).to be_frozen
        expect(parsed.to_hash).to eq(value.to_hash)
        expect(input).not_to be_frozen
        expect(input).not_to be_closed
        input.string << "\n"
        expect(parsed.to_hash).to eq(value.to_hash)
      end

      it 'borrows native YAML Tempfile input and seals parsed domain data' do
        value = klass.new(attributes)
        input = Tempfile.new(['immutable-yaml', '.yaml'])
        begin
          input.write(value.to_yaml)
          input.rewind
          parsed = klass.from_yaml(input)
          expect(parsed).to be_frozen
          expect(parsed.to_hash).to eq(value.to_hash)
          expect(input).not_to be_frozen
          expect(input).not_to be_closed
        ensure
          input.close!
        end
      end

      it 'serializes repeatedly without changing owned state or adapter output' do
        value = klass.new(attributes)
        before = Marshal.dump(value.instance_variables.to_h { |key| [key, value.instance_variable_get(key)] })
        2.times do
          value.to_json
          value.to_yaml
          value.to_hash
          next unless value.respond_to?(:to_neo4j_properties)

          properties = value.to_neo4j_properties
          parsed = klass.from_neo4j_record(properties.transform_keys(&:to_s))
          expect(parsed).to be_frozen
          expect(parsed.to_neo4j_properties).to eq(properties)
          expect(parsed.neo4j_labels).to eq(value.neo4j_labels)
        end
        expect(Marshal.dump(value.instance_variables.to_h { |key| [key, value.instance_variable_get(key)] })).to eq(before)
      end
    end
  end

  it 'copies and seals attached String and Date state without freezing caller data' do
    city = 'City'.dup
    city.instance_variable_set(:@metadata, { 'tags' => ['caller'.dup] })
    date = Date.new(1964, 2, 29)
    date.instance_variable_set(:@metadata, ['caller'.dup])
    value = Ammitto::Ontology::ValueObjects::BirthInfo.new(city: city, date: date)
    city.instance_variable_get(:@metadata)['tags'].first << ' changed'
    date.instance_variable_get(:@metadata).first << ' changed'
    expect(value.city.instance_variable_get(:@metadata)).to eq('tags' => ['caller'])
    expect(value.date.instance_variable_get(:@metadata)).to eq(['caller'])
    expect(value.city.instance_variable_get(:@metadata)['tags'].first).to be_frozen
    expect(value.date.instance_variable_get(:@metadata).first).to be_frozen
    expect(city).not_to be_frozen
    expect(date).not_to be_frozen
  end

  it 'rejects cyclic attached ownership without altering the caller' do
    date = Date.new(1964, 2, 29)
    date.instance_variable_set(:@cycle, date)
    expect { Ammitto::Ontology::ValueObjects::BirthInfo.new(date: date) }.to raise_error(ArgumentError, /Cyclic/)
    expect(date).not_to be_frozen
    expect(date.instance_variable_get(:@cycle)).to equal(date)
  end

  it 'preserves configuration adapter identity and caller options' do
    adapter = Lutaml::Model::Config.adapter_for(:json)
    options = { adapter: adapter }.freeze
    value = Ammitto::Ontology::ValueObjects::NameVariant.from_json('{"full_name":"Configured"}', options)
    expect(value).to be_frozen
    expect(value.full_name).to eq('Configured')
    expect(options[:adapter]).to equal(adapter)
    expect(adapter).not_to be_frozen
  end

  it 'retains framework parent and register identity without freezing shared state' do
    klass = Ammitto::Ontology::ValueObjects::NameVariant
    register = Lutaml::Model::Register.new(:default)
    parent = Ammitto::Ontology::Entities::PersonEntity.new(id: 'https://example.org/person')
    mutable = klass.send(:hydration_model).new({ full_name: 'Owned name' }, register: register)
    mutable.lutaml_parent = parent
    mutable.lutaml_root = parent
    value = klass.apply_mappings({}, :json, instance: mutable, register: register)
    expect(value).to be_frozen
    expect(value.lutaml_parent).to equal(parent)
    expect(value.lutaml_root).to equal(parent)
    expect(register).not_to be_frozen
    parent.id = 'https://example.org/changed'
    expect(value.full_name).to eq('Owned name')
    expect(parent).not_to be_frozen
  end

  it 'owns real nested Lutaml models in attached state without freezing caller models' do
    localized = Ammitto::Ontology::ValueObjects::LocalizedString.new(value: 'Quoted', language: 'en')
    date = Date.new(1964, 2, 29)
    date.instance_variable_set(:@metadata, { 'texts' => [localized] })
    value = Ammitto::Ontology::ValueObjects::BirthInfo.new(date: date)
    localized.value = 'Caller changed'
    owned = value.date.instance_variable_get(:@metadata)['texts'].first
    expect(owned).to be_frozen
    expect(owned.value).to eq('Quoted')
    expect(owned.value).to be_frozen
    expect(localized).not_to be_frozen
  end

  it 'owns container attached state and rejects attached container cycles' do
    [[], {}].each do |container|
      attached = ['caller'.dup]
      container.instance_variable_set(:@attached, attached)
      date = Date.new(1964, 2, 29)
      date.instance_variable_set(:@metadata, container)
      value = Ammitto::Ontology::ValueObjects::BirthInfo.new(date: date)
      owned = value.date.instance_variable_get(:@metadata)
      expect(owned.instance_variable_get(:@attached)).to eq(['caller'])
      expect(owned.instance_variable_get(:@attached)).not_to equal(attached)
      expect(owned.instance_variable_get(:@attached)).to be_frozen
      expect(owned.instance_variable_get(:@attached).first).to be_frozen
      restored = Marshal.load(Marshal.dump(value))
      restored_attached = restored.date.instance_variable_get(:@metadata).instance_variable_get(:@attached)
      expect(restored_attached).to eq(['caller'])
      expect(restored_attached).to be_frozen
      expect(restored_attached.first).to be_frozen
      attached.first << ' changed'
      expect(owned.instance_variable_get(:@attached)).to eq(['caller'])
      expect(container).not_to be_frozen
      container.instance_variable_set(:@cycle, container)
      expect { Ammitto::Ontology::ValueObjects::BirthInfo.new(date: date) }.to raise_error(ArgumentError, /Cyclic/)
      expect(container.instance_variable_get(:@cycle)).to equal(container)
    end
  end

  it 'restores Marshal borrowed parent cycles without freezing the parent' do
    klass = Ammitto::Ontology::ValueObjects::NameVariant
    parent = Ammitto::Ontology::Entities::PersonEntity.new(id: 'https://example.org/person')
    mutable = klass.send(:hydration_model).new(full_name: 'Owned name')
    mutable.lutaml_parent = parent
    mutable.lutaml_root = parent
    value = klass.apply_mappings({}, :json, instance: mutable)
    parent.names = [value]
    restored = Marshal.load(Marshal.dump(parent))
    name = restored.names.first
    expect(name).to be_frozen
    expect(name.full_name).to be_frozen
    expect(name.lutaml_parent).to equal(restored)
    expect(name.lutaml_root).to equal(restored)
    expect(restored).not_to be_frozen
    restored.id = 'https://example.org/changed'
    expect(name.full_name).to eq('Owned name')
  end

  it 'rejects extensions that alter field types, defaults, options or mappings' do
    klass = Ammitto::Ontology::ValueObjects::NameVariant
    extensions = [
      Class.new(klass) { attribute :full_name, :integer },
      Class.new(klass) { attribute :full_name, :string, default: 'New default' },
      Class.new(klass) { attribute :full_name, :string, collection: true },
      Class.new(klass) { json { map 'renamed', to: :full_name } }
    ]
    extensions.each do |extension|
      expect { extension.new(full_name: '123') }.to raise_error(ArgumentError, /matching hydration definition/)
      expect { extension.from_json('{}') }.to raise_error(ArgumentError, /matching hydration definition/)
    end
    expect(Class.new(klass).new(full_name: 'Unchanged').full_name).to eq('Unchanged')
  end

  it 'rejects extensions with custom mapping transforms' do
    klass = Ammitto::Ontology::ValueObjects::NameVariant
    transformer = Class.new(Lutaml::Model::ValueTransformer)
    transformer.define_singleton_method(:from) { |value, _format| value&.upcase }
    transformer.define_singleton_method(:to) { |value, _format| value }
    transformer.define_singleton_method(:can_transform?) { |_direction, _format| true }
    fields = klass.attributes.keys
    extension = Class.new(klass) do
      json do
        fields.each do |key|
          if key == :full_name
            map key, to: key, transform: transformer
          else
            map key, to: key
          end
        end
      end
    end
    expect { extension.from_json('{"full_name":"Mixed case"}') }
      .to raise_error(ArgumentError, /matching hydration definition/)
  end

  it 'leaves legacy flat value objects mutable' do
    name = Ammitto::NameVariant.new(full_name: 'Before')
    name.full_name = 'After'
    expect(name.full_name).to eq('After')
    expect(name).not_to be_frozen
  end
end
