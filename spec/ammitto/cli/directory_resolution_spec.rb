# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/cli'
%w[status fetch harmonize export].each { |c| require "ammitto/cli/#{c}_command" }

RSpec.describe 'CLI directory resolution' do
  around do |example|
    saved = ENV.fetch('AMMITTO_CACHE_DIR', nil)
    ENV['AMMITTO_CACHE_DIR'] = '/tmp/ammitto-cli-env'
    Ammitto.reset_configuration!
    example.run
  ensure
    ENV['AMMITTO_CACHE_DIR'] = saved
    Ammitto.reset_configuration!
  end

  # Thor fills an unset flag with its declared default, which would mask
  # the environment before the resolver ever sees it.
  it 'declares --cache-dir without a default' do
    expect(Ammitto::CLI.class_options[:cache_dir].default).to be_nil
  end

  {
    'status' => -> { Ammitto::Cmd::StatusCommand.new({}) },
    'fetch' => -> { Ammitto::Cmd::FetchCommand.new({}, ['uk']) },
    'harmonize' => -> { Ammitto::Cmd::HarmonizeCommand.new({}, []) },
    'export' => -> { Ammitto::Cmd::ExportCommand.new({}, 'jsonld') }
  }.each do |name, build|
    it "#{name} falls back to the configured cache directory" do
      expect(build.call.send(:cache_dir)).to eq(File.expand_path('/tmp/ammitto-cli-env'))
    end

    it "#{name} lets --cache-dir win" do
      command = build.call
      command.instance_variable_set(:@options, { cache_dir: '/tmp/flag' })
      expect(command.send(:cache_dir)).to eq('/tmp/flag')
    end
  end

  it 'harmonize --scan looks in the configured sources directory' do
    Dir.mktmpdir('ammitto-sources') do |dir|
      FileUtils.mkdir(File.join(dir, 'data-uk'))
      Ammitto.configure { |c| c.sources_dir = dir }
      command = Ammitto::Cmd::HarmonizeCommand.new({ scan: true }, [])

      expect(command.sources).to eq([:uk])
    end
  end
end
