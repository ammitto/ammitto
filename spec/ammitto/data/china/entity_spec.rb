# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/china'

RSpec.describe Ammitto::Data::China::Entity do
  describe '.new' do
    it 'creates a person entity' do
      entity = build_person_entity

      expect(entity.type).to eq('person')
      expect(entity.names).not_to be_empty
    end

    it 'creates an organization entity' do
      entity = build_organization_entity

      expect(entity.type).to eq('organization')
    end
  end

  describe '#primary_name' do
    it 'returns the primary name' do
      entity = build_person_entity(names: [
                                     build_name(lang: 'zh-Hans', value: '张三', is_primary: true),
                                     build_name(lang: 'en', value: 'Zhang San', is_primary: false)
                                   ])

      expect(entity.primary_name('zh-Hans')).to eq('张三')
      # primary_name without argument returns first primary name
      expect(entity.primary_name).to eq('张三')
    end

    it 'returns first name when no primary is marked' do
      entity = build_person_entity(names: [
                                     build_name(lang: 'zh-Hans', value: '李四'),
                                     build_name(lang: 'en', value: 'Li Si')
                                   ])

      expect(entity.primary_name).to eq('李四')
    end
  end

  describe '#person? and #organization?' do
    it 'returns true for person type' do
      entity = build_person_entity
      expect(entity.person?).to be true
      expect(entity.organization?).to be false
    end

    it 'returns true for organization type' do
      entity = build_organization_entity
      expect(entity.person?).to be false
      expect(entity.organization?).to be true
    end
  end

  describe '#slug' do
    it 'generates URL-safe slug from name' do
      entity = build_person_entity(names: [
                                     build_name(value: 'John Doe')
                                   ])

      expect(entity.slug).to eq('john-doe')
    end

    it 'handles Chinese characters' do
      entity = build_person_entity(names: [
                                     build_name(value: '张三')
                                   ])

      slug = entity.slug
      expect(slug).not_to be_empty
    end
  end

  def build_person_entity(attrs = {})
    Ammitto::Data::China::Entity.new({
      type: 'person',
      names: [build_name(lang: 'zh-Hans', value: '测试')],
      gender: 'male'
    }.merge(attrs))
  end

  def build_organization_entity(attrs = {})
    Ammitto::Data::China::Entity.new({
      type: 'organization',
      names: [build_name(lang: 'zh-Hans', value: '测试公司')]
    }.merge(attrs))
  end

  def build_name(attrs = {})
    Ammitto::Data::China::Entity::Name.new({
      value: 'Test',
      lang: 'zh-Hans',
      is_primary: true
    }.merge(attrs))
  end
end
