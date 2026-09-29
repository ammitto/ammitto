# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ammitto'

# A cached source file that does not parse is served until its TTL
# expires, so without handling it one bad file fails every search that
# includes that source.
RSpec.describe 'search when a cached source file is corrupt' do
  let(:cache_dir) { Dir.mktmpdir('ammitto-corrupt') }
  let(:cache_file) { File.join(cache_dir, 'cache', 'sources', 'eu.jsonld') }

  before do
    allow(Ammitto.configuration).to receive(:cache_dir).and_return(cache_dir)
    FileUtils.mkdir_p(File.dirname(cache_file))
    File.write(cache_file, '{"@graph": [{"names": [')
    allow(Faraday).to receive(:get)
      .and_raise(Faraday::ConnectionFailed.new('offline in specs'))
  end

  after { FileUtils.remove_entry(cache_dir) }

  it 'raises CacheError from load_data and removes the file' do
    source = Ammitto::Registry.instance(:eu)

    expect { source.load_data }.to raise_error(Ammitto::CacheError, /eu/)
    expect(File.exist?(cache_file)).to be(false)
  end

  it 'lets the search finish and reports the source as skipped' do
    results = nil
    expect { results = Ammitto.search('x', sources: [:eu]) }.not_to raise_error
    expect(results.skipped_sources).to eq([:eu])
    expect(results).not_to be_complete
  end

  it 'keeps a valid file another process installed after the corrupt read' do
    good = '{"@graph": []}'
    allow(MultiJson).to receive(:load).and_wrap_original do |original, content, *rest|
      Ammitto::Utils::AtomicFile.write(cache_file, good)
      original.call(content, *rest)
    end

    expect { Ammitto::Registry.instance(:eu).load_data }
      .to raise_error(Ammitto::CacheError)
    expect(File.read(cache_file)).to eq(good)
  end

  it 'keeps a valid file installed between the identity check and the removal' do
    good = '{"@graph": []}'
    swapped = false
    allow(File).to receive(:stat).and_wrap_original do |original, path|
      stat = original.call(path)
      if path == cache_file && !swapped
        swapped = true
        Ammitto::Utils::AtomicFile.write(cache_file, good)
      end
      stat
    end

    expect { Ammitto::Registry.instance(:eu).load_data }
      .to raise_error(Ammitto::CacheError)
    expect(File.read(cache_file)).to eq(good)
    expect(Dir.children(File.dirname(cache_file))).to eq(['eu.jsonld'])
  end

  it 'drops the quarantine when a newer file arrives before the link back' do
    first = '{"@graph": [1]}'
    second = '{"@graph": [2]}'
    pending_writes = { cache_file => first, '.corrupt' => second }
    allow(File).to receive(:stat).and_wrap_original do |original, path|
      stat = original.call(path)
      key = path.end_with?('.corrupt') ? '.corrupt' : path
      content = pending_writes.delete(key)
      Ammitto::Utils::AtomicFile.write(cache_file, content) if content
      stat
    end

    link_errors = []
    allow(File).to receive(:link).and_wrap_original do |original, *args|
      original.call(*args)
    rescue Errno::EEXIST => e
      link_errors << e
      raise
    end

    expect { Ammitto::Registry.instance(:eu).load_data }
      .to raise_error(Ammitto::CacheError)
    expect(link_errors.size).to eq(1)
    expect(File.read(cache_file)).to eq(second)
    expect(Dir.children(File.dirname(cache_file))).to eq(['eu.jsonld'])
  end
end
