# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::BaseSource do
  let(:source) { Class.new(described_class) { def code = :tr }.new }
  let(:cache_dir) { Dir.mktmpdir('ammitto-base-source') }
  let(:seen) { {} }

  before do
    allow(Ammitto.configuration).to receive_messages(cache_dir: cache_dir, read_timeout: 3,
                                                     connection_timeout: 2)
    allow(Faraday::Adapter::NetHttp).to receive(:new).and_wrap_original do |original, app, *rest|
      adapter = original.call(app, *rest)
      allow(adapter).to receive(:call) do |env|
        seen[:timeout] = env.request.timeout
        seen[:open_timeout] = env.request.open_timeout
        raise Faraday::ConnectionFailed, 'stubbed'
      end
      adapter
    end
  end

  after { FileUtils.remove_entry(cache_dir) }

  it 'downloads with the configured timeouts' do
    expect { source.download_to_cache }.to raise_error(Ammitto::NetworkError)
    expect(seen).to eq(timeout: 3, open_timeout: 2)
  end
end
