# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Configuration do
  provider = Ammitto::Config::EnvProvider
  env_names = (provider::ENV_MAPPING.values + provider::ENV_ALIASES.values)
              .map { |name| "#{provider::PREFIX}#{name}" }
              .push(provider::LEGACY_VERBOSE)

  around do |example|
    saved = env_names.to_h { |name| [name, ENV.fetch(name, nil)] }
    env_names.each { |name| ENV.delete(name) }
    example.run
  ensure
    saved.each { |name, value| ENV[name] = value }
    Ammitto.reset_configuration!
  end

  it 'uses the defaults when no environment variable is set' do
    config = described_class.new

    expect([config.cache_dir, config.api_base_url, config.verbose])
      .to eq([Ammitto::Config::Defaults::CACHE_DIR, Ammitto::Config::Defaults::API_BASE_URL,
              Ammitto::Config::Defaults::VERBOSE])
  end

  it 'honours the documented environment variables' do
    ENV['AMMITTO_CACHE_DIR'] = '/tmp/ammitto-env-cache'
    ENV['AMMITTO_API_BASE_URL'] = 'http://api.example/v1'
    ENV['AMMITTO_CACHE_TTL'] = '60'
    ENV['AMMITTO_READ_TIMEOUT'] = '7'
    config = described_class.new

    expect([config.cache_dir, config.api_base_url, config.cache_ttl, config.read_timeout])
      .to eq([File.expand_path('/tmp/ammitto-env-cache'), 'http://api.example/v1', 60, 7])
  end

  it 'reports the parse failure mode the environment selects' do
    ENV['AMMITTO_PARSE_FAILURE_MODE'] = 'raise'

    expect(described_class.new.parse_failure_mode).to eq(:raise)
  end

  it 'lets an explicit assignment win over the environment' do
    ENV['AMMITTO_CACHE_DIR'] = '/tmp/ammitto-env-cache'
    Ammitto.reset_configuration!
    Ammitto.configure { |c| c.cache_dir = '/tmp/explicit' }

    expect(Ammitto.configuration.cache_dir).to eq('/tmp/explicit')
  end

  it 'reads the environment again on reset!' do
    config = described_class.new
    ENV['AMMITTO_CACHE_DIR'] = '/tmp/ammitto-env-cache'
    config.reset!

    expect(config.cache_dir).to eq(File.expand_path('/tmp/ammitto-env-cache'))
  end
end
