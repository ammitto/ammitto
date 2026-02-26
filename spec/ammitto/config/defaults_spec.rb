# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ammitto/config/defaults'

RSpec.describe Ammitto::Config::Defaults do
  describe '::DATA_REPO_TO_SOURCE' do
    it 'contains all expected source mappings' do
      expect(described_class::DATA_REPO_TO_SOURCE).to include(
        'data-eu' => :eu,
        'data-un' => :un,
        'data-us' => :us,
        'data-uk' => :uk,
        'data-au' => :au,
        'data-ca' => :ca,
        'data-ch' => :ch,
        'data-cn' => :cn,
        'data-ru' => :ru,
        'data-tr' => :tr,
        'data-nz' => :nz,
        'data-jp' => :jp,
        'data-wb' => :wb,
        'data-eu-vessels' => :eu_vessels,
        'data-un-vessels' => :un_vessels
      )
    end

    it 'has 15 source mappings' do
      expect(described_class::DATA_REPO_TO_SOURCE.length).to eq(15)
    end
  end

  describe '::detect_data_repositories' do
    let(:temp_dir) { Dir.mktmpdir('ammitto_config_test') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns empty array for non-existent directory' do
      result = described_class.detect_data_repositories('/non/existent/path')
      expect(result).to eq([])
    end

    it 'returns empty array for directory without data-* repos' do
      FileUtils.mkdir_p(File.join(temp_dir, 'other-dir'))
      result = described_class.detect_data_repositories(temp_dir)
      expect(result).to eq([])
    end

    it 'detects single data-* repository' do
      FileUtils.mkdir_p(File.join(temp_dir, 'data-eu'))
      result = described_class.detect_data_repositories(temp_dir)
      expect(result).to contain_exactly(:eu)
    end

    it 'detects multiple data-* repositories' do
      FileUtils.mkdir_p(File.join(temp_dir, 'data-eu'))
      FileUtils.mkdir_p(File.join(temp_dir, 'data-un'))
      FileUtils.mkdir_p(File.join(temp_dir, 'data-us'))
      FileUtils.mkdir_p(File.join(temp_dir, 'other-dir'))

      result = described_class.detect_data_repositories(temp_dir)
      expect(result).to contain_exactly(:eu, :un, :us)
    end

    it 'detects all 15 source repositories' do
      described_class::DATA_REPO_TO_SOURCE.each_key do |repo_name|
        FileUtils.mkdir_p(File.join(temp_dir, repo_name))
      end

      result = described_class.detect_data_repositories(temp_dir)
      expect(result.length).to eq(15)
      expect(result).to match_array(described_class::ALL_SOURCES)
    end

    it 'ignores files named data-*' do
      FileUtils.mkdir_p(File.join(temp_dir, 'data-eu'))
      File.write(File.join(temp_dir, 'data-file'), 'content')

      result = described_class.detect_data_repositories(temp_dir)
      expect(result).to contain_exactly(:eu)
    end

    it 'ignores unknown data-* directories' do
      FileUtils.mkdir_p(File.join(temp_dir, 'data-eu'))
      FileUtils.mkdir_p(File.join(temp_dir, 'data-unknown'))

      result = described_class.detect_data_repositories(temp_dir)
      expect(result).to contain_exactly(:eu)
    end
  end

  describe '::ALL_SOURCES' do
    it 'contains all 15 sources' do
      expect(described_class::ALL_SOURCES.length).to eq(15)
      expect(described_class::ALL_SOURCES).to contain_exactly(
        :eu, :un, :us, :uk, :au, :ca, :ch, :cn, :ru, :tr, :nz, :jp, :wb,
        :eu_vessels, :un_vessels
      )
    end
  end
end
