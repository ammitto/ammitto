# frozen_string_literal: true

require 'date'

# Builds a model instance with every attribute set to its own sentinel,
# nested graphs included (two levels deep), so a conversion that drops,
# swaps or truncates any one field changes the result.
module CompatibilitySentinels
  module_function

  def build(klass, depth = 0)
    attributes = klass.attributes.each_with_index.to_h do |(name, attribute), index|
      [name, value(klass, name, attribute, index, depth)]
    end
    klass.new(attributes.compact)
  end

  def value(klass, name, attribute, index, depth)
    return discriminator(klass) if name == :entity_type && discriminator(klass)

    one = scalar(klass, name, attribute, index, depth)
    return one unless attribute.collection?

    # Past the depth limit there is nothing to put in the collection;
    # leave it unset rather than empty (the wire does not tell [] from nil)
    [one, scalar(klass, name, attribute, index + 50, depth)].compact.then { |items| items.empty? ? nil : items }
  end

  # An entity subclass fixes its entity_type; any other sentinel would be
  # a genuine conflict rather than a field to carry.
  def discriminator(klass)
    concept, side = Ammitto::Ontology::Contracts.lookup(klass)
    return nil unless concept

    side == :legacy ? concept.legacy_defaults[:entity_type] : klass.new.entity_type
  end

  def scalar(klass, name, attribute, index, depth)
    type = attribute.type
    return (depth < 2 ? build(type, depth + 1) : nil) if type.is_a?(Class) && type <= Lutaml::Model::Serializable

    case type.name.split('::').last
    when 'String' then "#{klass.name.split('::').last}.#{name}.#{index}"
    when 'Date' then Date.new(2024, 2, 29) + index
    when 'Integer' then 1000 + index
    when 'Float' then 10.0 + index
    when 'Boolean' then true
    when 'Hash' then { "#{name}.key" => "#{name}.value", 'nested' => { 'list' => ['a', index] } }
    else raise "no sentinel for #{klass}##{name} (#{type})"
    end
  end
end
