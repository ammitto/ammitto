# frozen_string_literal: true

require 'tmpdir'
require 'ammitto'

RSpec.describe Ammitto::Utils::AtomicFile do
  let(:dir) { Dir.mktmpdir('ammitto-atomic') }
  let(:path) { File.join(dir, 'eu.jsonld') }

  after { FileUtils.remove_entry(dir) }

  it 'writes the content and leaves no temp file behind' do
    described_class.write(path, '{"a":1}')

    expect(File.read(path)).to eq('{"a":1}')
    expect(Dir.children(dir)).to eq(['eu.jsonld'])
  end

  it 'keeps the previous file intact when the write is interrupted' do
    File.write(path, '{"old":true}')
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).with(/\.tmp\z/, any_args).and_wrap_original do |original, *args|
      original.call(*args) do |file|
        file.write('{"n')
        raise IOError, 'disk full'
      end
    end

    expect { described_class.write(path, '{"new":true}') }.to raise_error(IOError)
    expect(File.read(path)).to eq('{"old":true}')
    expect(Dir.children(dir)).to eq(['eu.jsonld'])
  end

  it 'preserves the mode of the file it replaces', skip: Gem.win_platform? && 'POSIX modes' do
    File.write(path, 'old')
    File.chmod(0o640, path)

    described_class.write(path, 'new')

    expect(File.stat(path).mode & 0o777).to eq(0o640)
  end

  it 'never reuses or removes a temp name another writer holds' do
    taken = File.join(dir, '.eu.jsonld.aaaa.tmp')
    File.write(taken, 'theirs')
    allow(SecureRandom).to receive(:hex).and_return('aaaa', 'bbbb')

    described_class.write(path, 'mine')

    expect(File.read(taken)).to eq('theirs')
    expect(File.read(path)).to eq('mine')
  end

  it 'gives up with a clear error when every temp name is taken' do
    File.write(File.join(dir, '.eu.jsonld.aaaa.tmp'), 'theirs')
    calls = 0
    allow(SecureRandom).to receive(:hex) do
      calls += 1
      raise 'unbounded retry' if calls > 50

      'aaaa'
    end

    expect { described_class.write(path, 'mine') }
      .to raise_error(Ammitto::CacheError, /unique temp file.*10 attempts/)
    expect(calls).to eq(10)
  end

  context 'when rename cannot replace in one step (Windows)' do
    before { allow(Gem).to receive(:win_platform?).and_return(true) }

    it 'replaces the file and removes the set-aside copy' do
      File.write(path, 'old')

      described_class.write(path, 'new')

      expect(File.read(path)).to eq('new')
      expect(Dir.children(dir)).to eq(['eu.jsonld'])
    end

    it 'restores the old file when the new one cannot be moved in' do
      File.write(path, 'old')
      allow(File).to receive(:rename).and_call_original
      allow(File).to receive(:rename).with(/\.tmp\z/, path).and_raise(Errno::EACCES)

      expect { described_class.write(path, 'new') }.to raise_error(Errno::EACCES)
      expect(File.read(path)).to eq('old')
      expect(Dir.children(dir)).to eq(['eu.jsonld'])
    end

    it 'keeps the set-aside copy and names both failures when rollback fails' do
      File.write(path, 'old')
      allow(File).to receive(:rename).and_call_original
      allow(File).to receive(:rename).with(/\.tmp\z/, path).and_raise(Errno::EACCES)
      allow(File).to receive(:rename).with(/\.tmp\.old\z/, path).and_raise(Errno::EPERM)

      expect { described_class.write(path, 'new') }
        .to raise_error(Ammitto::CacheError, /EACCES.*EPERM.*kept at .*\.tmp\.old/)
      aside = Dir.children(dir).grep(/\.old\z/)
      expect(aside.size).to eq(1)
      expect(File.read(File.join(dir, aside.first))).to eq('old')
    end
  end
end
