# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ammitto/data/japan/validator'

RSpec.describe Ammitto::Validation::FileSchemaValidator do
  let(:tmpdir) { Dir.mktmpdir('ammitto_validation_test') }

  let(:valid_china_yaml) do
    <<~YAML
      announcement:
        title: "关于对有关实体实施制裁的公告"
        url: "https://www.mfa.gov.cn/announcement/1"
        publish_date: "2025-01-15"
        authority: "外交部"
        type: "制裁公告"
        document_id: "第4号"
        signatory: "外交部"
        content: "公告内容"
      sanction_details:
        instruments:
          - law: "反外国制裁法"
        entities:
          - name:
              zh-Hans: "测试实体"
              en: "Test Entity"
            type: organization
            effective_date: "2025-01-15"
            sanction_list: "反制裁清单"
            reason:
              - zh-Hans: "原因"
            measures:
              - type:
                  - asset_freeze
                zh-Hans: "冻结资产"
    YAML
  end

  let(:invalid_china_yaml) do
    <<~YAML
      announcement:
        title: "缺少制裁详情"
    YAML
  end

  after { FileUtils.rm_rf(tmpdir) }

  def write_file(name, content)
    path = File.join(tmpdir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  describe '#initialize' do
    it 'raises UnknownCountryError for an unregistered country' do
      expect { described_class.new(country: :atlantis) }
        .to raise_error(Ammitto::Validation::UnknownCountryError,
                        /Unknown country: :atlantis/)
    end

    it 'accepts a string country key' do
      validator = described_class.new(country: 'china')
      expect(validator.country).to eq(:china)
    end

    it 'exposes the country schemas directory' do
      validator = described_class.new(country: :china)
      expect(validator.schemas_dir)
        .to eq(Ammitto::Data::China::SchemaLoader::SCHEMAS_DIR)
    end
  end

  describe '#validate_file (china)' do
    subject(:validator) { described_class.new(country: :china) }

    it 'returns a valid result for a schema-conforming file' do
      path = write_file('announcement.yml', valid_china_yaml)
      result = validator.validate_file(path)

      expect(result).to be_a(Ammitto::Validation::Result)
      expect(result.valid?).to be true
      expect(result.errors).to be_empty
      expect(result.details[:file]).to eq(path)
    end

    it 'returns schema errors for a non-conforming file' do
      path = write_file('announcement.yml', invalid_china_yaml)
      result = validator.validate_file(path)

      expect(result.valid?).to be false
      expect(result.errors.first[:path]).to eq(path)
      expect(result.errors.first[:message]).to match(/sanction_details/)
    end

    it 'reports a missing file' do
      result = validator.validate_file(File.join(tmpdir, 'nope.yml'))

      expect(result.valid?).to be false
      expect(result.error_messages).to eq(['File not found'])
    end

    it 'reports a YAML syntax error' do
      path = write_file('broken.yml', "announcement: [unclosed\n  nope")
      result = validator.validate_file(path)

      expect(result.valid?).to be false
      expect(result.error_messages.first).to match(/YAML syntax error/)
    end

    it 'reports an empty YAML file as invalid' do
      path = write_file('empty.yml', '')
      result = validator.validate_file(path)

      expect(result.valid?).to be false
      expect(result.error_messages).to eq(['YAML file is empty'])
    end
  end

  describe '#validate_files / #validate_directory (china)' do
    subject(:validator) { described_class.new(country: :china) }

    it 'walks a directory and reports per-file counts' do
      write_file('good.yml', valid_china_yaml)
      bad = write_file('bad.yml', invalid_china_yaml)

      result = validator.validate_directory(tmpdir)

      expect(result.valid?).to be false
      expect(result.details[:total_files]).to eq(2)
      expect(result.details[:valid_files]).to eq(1)
      expect(result.details[:invalid_files]).to eq(1)

      group = result.details[:file_errors].first
      expect(group[:file]).to eq(bad)
      expect(group[:errors].first[:message]).to match(/sanction_details/)
    end

    it 'flattens all file errors into Result#errors' do
      write_file('bad.yml', invalid_china_yaml)
      result = validator.validate_directory(tmpdir)

      expect(result.errors.length).to eq(1)
      expect(result.error_messages.first).to match(/sanction_details/)
    end

    it 'returns a valid result for a directory of valid files' do
      write_file('good.yml', valid_china_yaml)
      result = validator.validate_directory(tmpdir)

      expect(result.valid?).to be true
      expect(result.details[:invalid_files]).to eq(0)
    end

    it 'reports a missing sources directory' do
      result = validator.validate_directory(File.join(tmpdir, 'absent'))

      expect(result.valid?).to be false
      expect(result.error_messages.first)
        .to match(/Sources directory not found/)
      expect(result.details[:total_files]).to eq(0)
    end
  end

  describe 'japan' do
    subject(:validator) { described_class.new(country: :japan) }

    it 'reports a graceful error when the schema file is missing' do
      # 4 of Japan's 5 mapped schema files do not exist; the loader
      # raises SchemaNotFoundError, which must surface as an error, not
      # an exception.
      path = write_file('legal-instruments/fefta.yml',
                        "title: FEFTA\ncontent: text\n")
      result = validator.validate_file(path)

      expect(result.valid?).to be false
      expect(result.error_messages.first)
        .to match(/Schema not found: .*jp-legal-instrument\.yml/)
    end

    it 'memoizes missing schemas while still reporting them per file' do
      loader = Ammitto::Data::Japan::SchemaLoader
      allow(loader).to receive(:load).and_call_original

      paths = %w[a b].map do |name|
        write_file("legal-instruments/#{name}.yml",
                   "title: FEFTA\ncontent: text\n")
      end
      result = validator.validate_files(paths)

      expect(loader).to have_received(:load).once
      expect(result.details[:invalid_files]).to eq(2)
      expect(result.errors.length).to eq(2)
    end

    it 'reports the announcement schema draft as a schema error' do
      # jp-announcement.yml declares JSON Schema draft 2020-12, which
      # the json-schema gem cannot process; this must surface as a
      # graceful schema error.
      path = write_file('sanction-lists/entry.yml',
                        "announcement:\n  title: x\nsanction_details: {}\n")
      result = validator.validate_file(path)

      expect(result.valid?).to be false
      expect(result.error_messages.first).to match(/Schema error/)
    end
  end

  describe 'legacy country validator compatibility' do
    it 'Data::China::Validator#validate keeps its Boolean + #errors API' do
      good = write_file('good.yml', valid_china_yaml)
      bad = write_file('bad.yml', invalid_china_yaml)
      legacy = Ammitto::Data::China::Validator.new

      expect(legacy.validate(good)).to be true
      expect(legacy.errors).to be_empty
      expect(legacy.validate(bad)).to be false
      expect(legacy.errors.first).to include(:path, :message)
    end

    it 'Data::China::Validator#validate_files keeps the report shape' do
      good = write_file('good.yml', valid_china_yaml)
      bad = write_file('bad.yml', invalid_china_yaml)

      report = Ammitto::Data::China::Validator.new.validate_files([good, bad])

      expect(report).to include(valid: false, total_files: 2,
                                valid_files: 1, invalid_files: 1)
      expect(report[:errors].first[:file]).to eq(bad)
      expect(report[:errors].first[:errors].first[:message])
        .to match(/sanction_details/)
    end

    it 'Data::Japan::Validator#validate_all reports a missing directory' do
      report = Ammitto::Data::Japan::Validator.new
                                              .validate_all('/no/such/dir')

      expect(report).to include(valid: false, total_files: 0,
                                valid_files: 0, invalid_files: 0)
      expect(report[:errors].first[:message])
        .to match(/Sources directory not found/)
    end
  end

  describe 'Ammitto::Validation.file' do
    it 'validates a single file' do
      path = write_file('announcement.yml', valid_china_yaml)
      result = Ammitto::Validation.file(path, country: :china)

      expect(result.valid?).to be true
    end

    it 'validates a directory' do
      write_file('bad.yml', invalid_china_yaml)
      result = Ammitto::Validation.file(tmpdir, country: :china)

      expect(result.valid?).to be false
      expect(result.details[:total_files]).to eq(1)
    end

    it 'raises UnknownCountryError for an unregistered country' do
      expect { Ammitto::Validation.file(tmpdir, country: :mars) }
        .to raise_error(Ammitto::Validation::UnknownCountryError)
    end
  end
end
