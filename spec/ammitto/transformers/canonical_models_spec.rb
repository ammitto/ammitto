# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Transformers::CanonicalModels do
  it 'inherits a production transformer canonical entrypoint declaration' do
    subclass = Class.new(Ammitto::Sources::Wb::Transformer)
    expect(subclass).to be_canonical
    expect(subclass.canonical_entrypoint_names).to eq([:transform])
    expect(subclass.new).to respond_to(:canonical_transform)
  end

  it 'combines current ancestor declarations with isolated local declarations' do
    parent = Class.new(Ammitto::Transformers::BaseTransformer) do
      def transform(value)
        build_model(Ammitto::NameVariant, full_name: value)
      end
      canonical_entrypoints :transform
    end
    child = Class.new(parent)
    sibling = Class.new(parent)
    expect(child.canonical_entrypoint_names).to eq([:transform])
    child.class_eval do
      def extra(value)
        build_model(Ammitto::NameVariant, full_name: value)
      end
      canonical_entrypoints :extra
    end
    parent.class_eval do
      def later(value)
        build_model(Ammitto::NameVariant, full_name: value)
      end
      canonical_entrypoints :later
    end
    expect(parent.canonical_entrypoint_names).to eq(%i[transform later])
    expect(sibling.canonical_entrypoint_names).to eq(%i[transform later])
    expect(child.canonical_entrypoint_names).to eq(%i[transform later extra])
    expect(Class.new(child).canonical_entrypoint_names).to eq(%i[transform later extra])
    canonical = child.new(:wb).canonical_extra('Inherited name')
    legacy = child.new(:wb).extra('Inherited name')
    expect(canonical).to be_a(Ammitto::Ontology::ValueObjects::NameVariant)
    expect(canonical).to be_frozen
    expect(legacy).to be_a(Ammitto::NameVariant)
    expect(legacy).not_to be_frozen
    expect(legacy.full_name).to eq(canonical.full_name)
  end
end
