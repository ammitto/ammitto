# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Validation::ObjectValidator do
  subject(:validator) { described_class.new }

  describe '#validate with type: :entity' do
    let(:valid_entity) do
      {
        'id' => 'entity-1',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Jane Doe' }]
      }
    end

    it 'returns a valid result for a well-formed entity' do
      result = validator.validate(valid_entity, type: :entity)

      expect(result).to be_a(Ammitto::Validation::Result)
      expect(result.valid?).to be true
      expect(result.details[:type]).to eq(:entity)
    end

    it 'rejects an unknown entity type' do
      entity = valid_entity.merge('entityType' => 'robot')
      result = validator.validate(entity, type: :entity)

      expect(result.valid?).to be false
      expect(result.errors).to include('Invalid entity type: robot')
    end

    it 'accepts every Ontology::Types entity type' do
      Ammitto::Ontology::Types::ENTITY_TYPES.each do |type|
        entity = valid_entity.merge('entityType' => type.to_s)
        expect(validator.validate(entity, type: :entity).valid?).to be true
      end
    end

    it 'rejects an entity without names' do
      result = validator.validate({ 'id' => 'x', 'entityType' => 'person' },
                                  type: :entity)

      expect(result.valid?).to be false
      expect(result.errors).to include('Missing required field: names')
    end

    it 'rejects a name variant without any name component' do
      entity = valid_entity.merge('names' => [{ 'title' => 'Dr.' }])
      result = validator.validate(entity, type: :entity)

      expect(result.valid?).to be false
      expect(result.errors)
        .to include('names[0]: Must have fullName, firstName, or lastName')
    end
  end

  describe '#validate with type: :sanction_entry' do
    let(:valid_entry) do
      {
        'id' => 'entry-1',
        'entityId' => 'entity-1',
        'authority' => { 'id' => 'eu' },
        'status' => 'active'
      }
    end

    it 'returns a valid result for a well-formed entry' do
      result = validator.validate(valid_entry, type: :sanction_entry)
      expect(result.valid?).to be true
    end

    it 'accepts the harmonized StatusChange statuses' do
      Ammitto::StatusChange::STATUSES.each do |status|
        entry = valid_entry.merge('status' => status)
        expect(validator.validate(entry, type: :sanction_entry).valid?)
          .to be(true), "expected status #{status} to be valid"
      end
    end

    it 'rejects an unknown status' do
      entry = valid_entry.merge('status' => 'bogus')
      result = validator.validate(entry, type: :sanction_entry)

      expect(result.valid?).to be false
      expect(result.errors).to include('Invalid status: bogus')
    end

    it 'rejects an unknown authority' do
      entry = valid_entry.merge('authority' => { 'id' => 'zz' })
      result = validator.validate(entry, type: :sanction_entry)

      expect(result.valid?).to be false
      expect(result.errors).to include('Unknown authority: zz')
    end

    it 'reports missing required fields' do
      result = validator.validate({}, type: :sanction_entry)

      expect(result.valid?).to be false
      expect(result.errors).to include('Missing required field: id',
                                       'Missing required field: entityId')
    end
  end

  describe '#validate with type: :name_variant' do
    it 'accepts a variant with a name component' do
      result = validator.validate({ 'firstName' => 'Jane' },
                                  type: :name_variant)
      expect(result.valid?).to be true
    end

    it 'rejects a variant without any name component' do
      result = validator.validate({}, type: :name_variant)
      expect(result.valid?).to be false
    end
  end

  describe '#validate with type: :json_ld' do
    it 'accepts a document with @context and @graph' do
      result = validator.validate({ '@context' => {}, '@graph' => [] },
                                  type: :json_ld)
      expect(result.valid?).to be true
    end

    it 'rejects a document without JSON-LD keywords' do
      result = validator.validate({}, type: :json_ld)

      expect(result.valid?).to be false
      expect(result.errors).to include('Missing @context in JSON-LD')
    end
  end

  describe '#validate with an unknown type' do
    it 'raises ArgumentError' do
      expect { validator.validate({}, type: :galaxy) }
        .to raise_error(ArgumentError, /Unknown validation type: :galaxy/)
    end
  end

  describe 'enum routing through Ontology::Types' do
    it 'keeps Schema::Validator::ENTITY_TYPES aligned with the ontology' do
      expect(Ammitto::Schema::Validator::ENTITY_TYPES)
        .to eq(Ammitto::Ontology::Types::ENTITY_TYPES.map(&:to_s))
    end

    it 'keeps the legacy string values for API compatibility' do
      expect(Ammitto::Schema::Validator::ENTITY_TYPES)
        .to eq(%w[person organization vessel aircraft])
    end
  end

  describe 'Ammitto::Validation.object' do
    it 'validates through the facade entry point' do
      result = Ammitto::Validation.object(
        { 'id' => 'x', 'entityType' => 'vessel',
          'names' => [{ 'fullName' => 'MV Example' }] },
        type: :entity
      )
      expect(result.valid?).to be true
    end

    it 'works from a standalone require of ammitto/validation' do
      lib = File.expand_path('../../../lib', __dir__)
      script = 'require "ammitto/validation"; ' \
               'Ammitto::Validation.object({}, type: :entity)'
      expect(system(RbConfig.ruby, '-I', lib, '-e', script))
        .to be(true), 'ammitto/validation must load without full ammitto'
    end
  end
end
