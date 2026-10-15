# frozen_string_literal: true

require 'date'
require 'json'
require 'yaml'

# Drives the harmonize command's own #transform_data over the per-branch
# records in spec/fixtures/canonical_pipeline and records what crossed the
# serializer and exporter boundaries, so a spec can inspect the models the
# production path built as well as the JSON-LD it emitted.
#
# Constants are resolved inside the methods: spec_helper requires this file
# before `ammitto` itself.
module CanonicalPipelineFixtures
  ROOT = File.expand_path('../fixtures/canonical_pipeline', __dir__)

  # Six transformers (METI included) stamp retrieved_at with the clock and
  # WB derives a status from today's date, so goldens are captured and
  # compared at one pinned instant.
  PINNED_TIME = Time.utc(2026, 10, 14, 12, 0, 0)

  # Records each model the command hands to JsonLdSerializer. Construction
  # counting measures transformers separately from the serializer, which
  # reads canonical values through wire views.
  module SerializerRecorder
    attr_accessor :recorded_models

    def serialize_entity(entity)
      recorded_models << entity
      CanonicalPipelineFixtures.paused { super }
    end

    def serialize_entry(entry)
      recorded_models << entry
      CanonicalPipelineFixtures.paused { super }
    end
  end

  # Counts flat facade constructions while the harmonize path transforms a
  # record: a source that builds flat models and converts them afterwards
  # is not building canonical models.
  module FlatConstructionCounter
    def new(...)
      CanonicalPipelineFixtures.flat_constructions << name if CanonicalPipelineFixtures.counting
      super
    end
  end

  class << self
    attr_accessor :counting

    def flat_constructions
      @flat_constructions ||= []
    end

    def paused
      was = counting
      self.counting = false
      yield
    ensure
      self.counting = was
    end

    def count_flat_constructions
      Ammitto::Ontology::Contracts.registry.each_value do |concept|
        klass = concept.legacy_class
        klass.singleton_class.prepend(FlatConstructionCounter) unless klass.singleton_class < FlatConstructionCounter
      end
      flat_constructions.clear
      self.counting = true
      yield
    ensure
      self.counting = false
    end
  end

  # Stands in for the graph exporter, which #transform_data reaches only to
  # register an announcement's group; it keeps the hash the exporter would
  # have stored.
  class GroupRecorder
    attr_reader :groups

    def initialize
      @groups = []
    end

    def add_group(group, source:)
      @groups << { 'source' => source.to_s, 'group' => group.to_hash }
    end
  end

  module_function

  def manifest
    @manifest ||= YAML.safe_load_file(File.join(ROOT, 'manifest.yml'))
  end

  def branches
    manifest.fetch('branches')
  end

  def label(branch)
    "#{branch.fetch('source')}__#{branch.fetch('branch')}"
  end

  def fixture_path(branch)
    File.join(ROOT, branch.fetch('file'))
  end

  def golden_path(branch)
    File.join(ROOT, 'golden', "#{label(branch)}.json")
  end

  def load_record(branch)
    YAML.safe_load_file(fixture_path(branch), permitted_classes: [Date, Time],
                                              aliases: true)
  end

  # @return [Hash] output: what #transform_data returned, groups: what it
  #   registered with the exporter, models: what it serialized
  def run(branch)
    source = branch.fetch('source').to_sym
    command = Ammitto::Cmd::HarmonizeCommand.new({}, [source])
    serializer = command.send(:json_ld_serializer)
    serializer.singleton_class.prepend(SerializerRecorder)
    serializer.recorded_models = []
    exporter = GroupRecorder.new
    command.instance_variable_set(:@exporter, exporter)
    if branch['input_dir']
      index = command.send(:cn_modification_index, File.join(ROOT, branch['input_dir']))
      command.instance_variable_set(:@cn_modification_index, index)
    end

    record = load_record(branch)
    output = count_flat_constructions do
      command.send(:transform_data, source, record, file: fixture_path(branch))
    end
    { output: output, groups: exporter.groups, models: serializer.recorded_models,
      flat_constructions: flat_constructions.tally }
  end

  # @return [Array<Hash>] records of transformers outside the harmonize
  #   registry (METI)
  def extras
    manifest.fetch('extras')
  end

  # The METI transformer is outside the harmonize registry, so it is driven
  # directly and its result serialized by the serializer harmonize uses.
  # @param entrypoint [Symbol] canonical_transform, or transform for the
  #   legacy projection (and for the unmodified pipeline)
  # @return [Hash] the keys #run returns
  def run_extra(extra, entrypoint: :canonical_transform)
    record = load_record(extra)
    source = Ammitto::Data::Japan::Meti::Entity.new(**record.transform_keys(&:to_sym))
    transformer = Ammitto::Data::Japan::Meti::Transformer.new
    result = count_flat_constructions { transformer.public_send(entrypoint, source) }
    serializer = Ammitto::Serialization::JsonLdSerializer.new
    output = { entity: serializer.serialize_entity(result[:entity]).except('@context'),
               entry: serializer.serialize_entry(result[:entry]).except('@context') }
    { output: output, groups: [], models: [result[:entity], result[:entry]],
      flat_constructions: flat_constructions.tally }
  end

  # The emitted document a golden file stores: the JSON text harmonize
  # writes, plus the Ruby class of every leaf, because JSON prints a Date
  # and its String spelling identically while the Turtle exporter does not.
  def wire_document(result)
    document = { 'output' => result.fetch(:output), 'groups' => result.fetch(:groups) }
    { 'json' => JSON.parse(JSON.generate(document)), 'leaf_types' => leaf_types(document) }
  end

  def leaf_types(value, path = '$', types = {})
    case value
    when Hash then value.each { |key, child| leaf_types(child, "#{path}.#{key}", types) }
    when Array then value.each_with_index { |child, i| leaf_types(child, "#{path}[#{i}]", types) }
    else types[path] = value.class.name
    end
    types
  end

  # Every Lutaml model reachable from the roots, through attributes and the
  # entries an entity holds outside its attributes.
  def reachable_models(roots)
    seen = {}.compare_by_identity
    stack = Array(roots).dup
    until stack.empty?
      value = stack.pop
      case value
      when Array then stack.concat(value)
      when Hash then stack.concat(value.values)
      when Lutaml::Model::Serializable
        next if seen.key?(value)

        seen[value] = true
        value.class.attributes.each_key { |name| stack << value.public_send(name) }
        stack.concat(Array(value.sanction_entries)) if value.respond_to?(:sanction_entries)
      end
    end
    seen.keys
  end
end
