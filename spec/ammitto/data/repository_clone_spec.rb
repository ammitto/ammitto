# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'ammitto'

# Helpers for the clone specs; they read the root and origin lets.
module RepositoryCloneSpecHelpers
  def git(*)
    output, status = Open3.capture2e('git', *)
    raise output unless status.success?
  end

  def make_origin
    work = File.join(root, 'work')
    git('init', '-q', work)
    File.write(File.join(work, 'marker'), 'origin')
    git('-C', work, '-c', 'user.name=t', '-c', 'user.email=t@t', 'add', '.')
    git('-C', work, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init')
    git('clone', '-q', '--bare', work, origin)
  end

  # A Windows path starts with its drive letter, and a file URL needs the
  # slash before it: file://localhost/D:/x, never file://localhostD:/x.
  def file_url(path)
    "file://localhost#{'/' unless path.start_with?('/')}#{path}"
  end
end

# `data clone --force --data-repository PATH` must not destroy a directory it
# did not create, and a failed re-clone must not leave nothing behind.
RSpec.describe Ammitto::Data::Repository do
  include RepositoryCloneSpecHelpers

  let(:root) { Dir.mktmpdir('ammitto-clone') }
  let(:target) { File.join(root, 'data') }
  let(:origin) { File.join(root, 'origin.git') }

  after { FileUtils.remove_entry(root) }

  context 'when the directory is not a clone' do
    before do
      FileUtils.mkdir_p(target)
      File.write(File.join(target, 'precious'), 'keep me')
    end

    it 'refuses and leaves the directory intact' do
      repo = described_class.new(local_path: target, remote_url: File.join(root, 'missing.git'))

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Refusing to replace/)
      expect(File.read(File.join(target, 'precious'))).to eq('keep me')
    end
  end

  context 'when the directory is a clone of a different remote' do
    before do
      make_origin
      git('clone', '-q', origin, target)
    end

    it 'refuses and leaves the clone intact' do
      repo = described_class.new(local_path: target, remote_url: 'https://example.invalid/other.git')

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Refusing to replace/)
      expect(File).to exist(File.join(target, 'marker'))
    end
  end

  context 'when the directory is a clone of the remote' do
    before do
      make_origin
      git('clone', '-q', origin, target)
      File.write(File.join(target, 'stale'), 'x')
    end

    it 'replaces it with a fresh clone' do
      described_class.new(local_path: target, remote_url: origin).clone(force: true)

      expect(File).to exist(File.join(target, 'marker'))
      expect(File).not_to exist(File.join(target, 'stale'))
    end

    it 'keeps the existing clone when the fresh clone fails' do
      repo = described_class.new(local_path: target, remote_url: origin)
      FileUtils.mv(origin, "#{origin}.gone")

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Failed to clone/)
      expect(File).to exist(File.join(target, 'stale'))
      expect(Dir.children(root)).to contain_exactly('data', 'origin.git.gone', 'work')
    end
  end

  context 'when the remote is a local path' do
    before do
      make_origin
      git('clone', '-q', origin, target)
      File.write(File.join(target, 'stale'), 'x')
    end

    it 'treats a path without the .git suffix as a different repository' do
      FileUtils.mkdir_p(File.join(root, 'origin'))
      repo = described_class.new(local_path: target, remote_url: File.join(root, 'origin'))

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Refusing to replace/)
      expect(File).to exist(File.join(target, 'stale'))
    end

    it 'matches a relative path that resolves to the same repository' do
      Dir.chdir(root) do
        described_class.new(local_path: target, remote_url: './work/../origin.git').clone(force: true)
      end

      expect(File).not_to exist(File.join(target, 'stale'))
    end
  end

  context 'when a local remote path looks like a URL' do
    before do
      make_origin
      git('clone', '-q', origin, target)
      File.write(File.join(target, 'stale'), 'x')
    end

    it 'keeps a path containing git@ on the path comparison' do
      mirror = File.join(root, 'git@mirror')
      git('clone', '-q', '--bare', origin, File.join(mirror, 'repo.git'))
      FileUtils.rm_rf(target)
      git('clone', '-q', File.join(mirror, 'repo.git'), target)
      FileUtils.mkdir_p(File.join(mirror, 'repo'))
      repo = described_class.new(local_path: target, remote_url: File.join(mirror, 'repo'))

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Refusing to replace/)
    end

    it 'reads a file://localhost URL as the absolute path it names' do
      described_class.new(local_path: target, remote_url: file_url(origin)).clone(force: true)

      expect(File).not_to exist(File.join(target, 'stale'))
    end

    it 'reads a drive-letter file URL as that drive on Windows' do
      allow(Gem).to receive(:win_platform?).and_return(true)
      repo = described_class.new(local_path: target, remote_url: origin)

      expect(repo.send(:local_remote_path, 'file:///C:/repo')).to eq('C:/repo')
    end

    it 'refuses when a path cannot be resolved' do
      allow(File).to receive(:realpath).and_raise(Errno::EACCES, 'simulated')
      repo = described_class.new(local_path: target, remote_url: origin)

      expect { repo.clone(force: true) }.to raise_error(Ammitto::Error, /Cannot resolve/)
      expect(File).to exist(File.join(target, 'stale'))
    end
  end

  context 'when replacing a clone' do
    before do
      make_origin
      git('clone', '-q', origin, target)
      File.write(File.join(target, 'stale'), 'x')
    end

    it 'leaves an unrelated sibling directory alone' do
      sibling = "#{target}.reclone-#{Process.pid}"
      FileUtils.mkdir_p(sibling)
      File.write(File.join(sibling, 'mine'), 'keep')

      described_class.new(local_path: target, remote_url: origin).clone(force: true)

      expect(File.read(File.join(sibling, 'mine'))).to eq('keep')
    end

    it 'restores the existing clone when the swap fails' do
      calls = 0
      allow(File).to receive(:rename).and_wrap_original do |original, *args|
        calls += 1
        raise Errno::EACCES, 'simulated' if calls == 2

        original.call(*args)
      end

      expect { described_class.new(local_path: target, remote_url: origin).clone(force: true) }
        .to raise_error(Errno::EACCES)
      expect(File).to exist(File.join(target, 'stale'))
      expect(Dir.children(root)).to contain_exactly('data', 'origin.git', 'work')
    end
  end

  describe 'reading local_path' do
    it 'keeps a path containing git@ as the local path' do
      path = File.join(root, 'git@mirror')
      repo = described_class.new(local_path: path)

      expect(repo.local_path).to eq(path)
      expect(repo.remote_url).to eq(described_class::DEFAULT_REMOTE_URL)
    end

    it 'keeps a relative path starting with git@ as the local path' do
      repo = described_class.new(local_path: 'git@mirror/repo')

      expect(repo.local_path).to eq('git@mirror/repo')
    end

    ['git@github.com:ammitto/data.git', 'ssh://git@github.com/ammitto/data.git',
     'git+ssh://git@github.com/ammitto/data.git', 'https://github.com/ammitto/data.git'].each do |url|
      it "takes #{url} as the remote" do
        repo = described_class.new(local_path: url)

        expect(repo.remote_url).to eq(url)
        expect(repo.local_path).to eq(described_class::DEFAULT_LOCAL_PATH)
      end
    end
  end
end
