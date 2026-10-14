# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ammitto/data/japan/validator'

# Fixtures are from ammitto/data-jp: both announcement layouts, FEFTA's
# first clause, and the actual Japanese supporting registries.
RSpec.describe 'Japan packaged schemas' do
  let(:validator) { Ammitto::Data::Japan::Validator.new }
  let(:fixtures) { File.expand_path('../../../fixtures/japan/validation', __dir__) }

  def validate_data(filename, data)
    Dir.mktmpdir do |dir|
      path = File.join(dir, filename)
      File.write(path, data.to_yaml)
      validator.validate(path)
    end
  end

  def fixture(filename)
    YAML.safe_load_file(File.join(fixtures, filename), aliases: true)
  end

  %w[export-prohibition.yml foreign-user-list.yml document-types.yml organizations.yml].each do |filename|
    it "accepts the source layout in #{filename}" do
      expect(validator.validate(File.join(fixtures, filename))).to be true
      expect(validator.errors).to be_empty
    end
  end

  it 'accepts a legal instrument with recursive source content' do
    expect(validate_data('law.yml', fixture('legal-instrument.yml'))).to be true
  end

  %w[export-prohibition.yml foreign-user-list.yml].each do |filename|
    it "rejects malformed entity measures in #{filename}" do
      data = fixture(filename)
      entities = data['entities'] || data.dig('sanction_details', 'entities')
      entities.first['measures'].first['type'] = 42
      expect(validate_data(filename, data)).to be false
    end
  end

  %w[document-types.yml organizations.yml].each do |filename|
    it "rejects non-string Japanese names in #{filename}" do
      data = fixture(filename)
      data.values.first.first['name']['ja'] = 42
      expect(validate_data(filename, data)).to be false
    end
  end

  it 'rejects wrong types in nested legal content' do
    data = fixture('legal-instrument.yml')
    data['content'].first['content'].first['content'] = 42
    expect(validate_data('law.yml', data)).to be false
  end

  it 'rejects an announcement without either entity layout' do
    data = fixture('export-prohibition.yml')
    data.delete('entities')
    expect(validate_data('notice.yml', data)).to be false
  end

  it 'accepts a missing English translation when a Japanese name exists' do
    data = fixture('export-prohibition.yml')
    data['entities'].first['name'] = { 'ja' => '名称', 'en' => nil }
    expect(validate_data('notice.yml', data)).to be true
  end

  [nil, '', '   '].each do |name|
    it "rejects an entity whose only name is #{name.inspect}" do
      data = fixture('foreign-user-list.yml')
      data['sanction_details']['entities'].first['name'] = { 'en' => name }
      expect(validate_data('notice.yml', data)).to be false
    end
  end

  it 'loads every advertised schema in an engine-supported dialect' do
    loader = Ammitto::Data::Japan::SchemaLoader
    loader.supported_types.each do |type|
      expect(loader.load(type)['$schema']).to eq('http://json-schema.org/draft-04/schema#')
    end
  end
end
