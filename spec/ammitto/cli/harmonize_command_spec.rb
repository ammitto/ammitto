# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  let(:sources_dir) { Dir.mktmpdir('ammitto_harmonize_test') }
  let(:options) { { sources_dir: sources_dir } }
  let(:command) { described_class.new(options, ['us']) }

  after do
    FileUtils.rm_rf(sources_dir)
  end

  # Create a file (plus its parent directories) under sources_dir
  def write_file(*segments)
    path = File.join(sources_dir, *segments)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\nid: test\n")
    path
  end

  # Create a directory under sources_dir
  def make_dir(*segments)
    path = File.join(sources_dir, *segments)
    FileUtils.mkdir_p(path)
    path
  end

  describe '#find_input_dir' do
    def find_input(source = :us)
      command.send(:find_input_dir, source)
    end

    def find_input_dir(source = :us)
      find_input(source)&.first
    end

    it 'prefers a populated processed/ directory' do
      write_file('data-us', 'processed', 'entities', 'entity.yaml')
      make_dir('data-us', 'sources', 'sanction-lists', 'sdn-list')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'processed'))
    end

    it 'falls through an empty processed/ to sources/sanction-lists' do
      make_dir('data-us', 'processed')
      entity = write_file('data-us', 'sources', 'sanction-lists',
                          'sdn-list', 'entity.yml')

      dir, files = find_input

      expect(dir).to eq(File.join(sources_dir, 'data-us', 'sources',
                                  'sanction-lists'))
      expect(files).to eq([entity])
    end

    it 'loads one-level and deeper files together when direct is empty' do
      make_dir('data-jp', 'processed')
      one = write_file('data-jp', 'sources', 'sanction-lists',
                       'fefta-list', 'entity.yml')
      deep = write_file('data-jp', 'sources', 'sanction-lists',
                        'mof-asset-freeze', '01-milosevic', '20260306.yml')

      _dir, files = find_input(:jp)

      expect(files).to contain_exactly(one, deep)
    end

    it 'falls through a processed/ holding only _index.yaml' do
      write_file('data-us', 'processed', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'sdn-list',
                 'entity.yml')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'sources',
                         'sanction-lists'))
    end

    it 'falls through unusable processed/ and sanction-lists to raw' do
      write_file('data-us', 'processed', '_index.yaml')
      make_dir('data-us', 'sources', 'sanction-lists')
      write_file('data-us', 'raw', '2026-01-02', 'entity.yaml')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'raw', '2026-01-02'))
    end

    it 'resolves hyphen-named repositories by eligibility' do
      make_dir('data-eu-vessels', 'processed')
      write_file('data-eu-vessels', 'sources', 'sanction-lists', 'list',
                 'vessel.yml')

      expect(find_input_dir(:eu_vessels))
        .to eq(File.join(sources_dir, 'data-eu-vessels', 'sources',
                         'sanction-lists'))
    end

    it 'prefers the underscore repository when both are eligible' do
      write_file('data-eu_vessels', 'processed', 'entity.yaml')
      write_file('data-eu-vessels', 'processed', 'entity.yaml')

      expect(find_input_dir(:eu_vessels))
        .to eq(File.join(sources_dir, 'data-eu_vessels', 'processed'))
    end

    it 'falls through to a usable cache when repo dirs are unusable' do
      make_dir('data-us', 'processed')
      cache_dir = make_dir('cache')
      options[:cache_dir] = cache_dir
      File.write(File.join(make_dir('cache', 'raw', 'us', '2026-01-01'),
                           'entity.yaml'), "---\nid: test\n")

      expect(find_input_dir)
        .to eq(File.join(cache_dir, 'raw', 'us', '2026-01-01'))
    end

    it 'reaches a usable cache past a raw/ dir without dated subdirs' do
      make_dir('data-us', 'raw')
      cache_dir = make_dir('cache')
      options[:cache_dir] = cache_dir
      File.write(File.join(make_dir('cache', 'raw', 'us', '2026-01-01'),
                           'entity.yaml'), "---\nid: test\n")

      expect(find_input_dir)
        .to eq(File.join(cache_dir, 'raw', 'us', '2026-01-01'))
    end

    it 'treats glob metacharacters in configured paths literally' do
      weird = File.join(sources_dir, 'we[i]rd')
      entity = File.join(weird, 'data-us', 'processed', 'entity.yaml')
      FileUtils.mkdir_p(File.dirname(entity))
      File.write(entity, "---\nid: test\n")
      options[:sources_dir] = weird

      dir, files = find_input

      expect(dir).to eq(File.join(weird, 'data-us', 'processed'))
      expect(files).to eq([entity])
    end

    it 'resolves each directory at most once per discovery call' do
      write_file('data-us', 'processed', '_index.yaml')

      resolved = []
      allow(command).to receive(:resolve_yaml_files)
        .and_wrap_original do |original, dir|
          resolved << dir
          original.call(dir)
        end

      find_input

      expect(resolved).to eq(resolved.uniq)
    end

    context 'when no candidate holds eligible YAML' do
      it 'returns the existing processed/ directory as before' do
        write_file('data-us', 'processed', '_index.yaml')

        expect(find_input_dir)
          .to eq(File.join(sources_dir, 'data-us', 'processed'))
      end

      it 'reports "No YAML files found" for that directory' do
        write_file('data-us', 'processed', '_index.yaml')

        result = command.send(:harmonize_source, :us)

        expect(result[:status]).to eq(:error)
        expect(result[:error]).to eq('No YAML files found')
      end

      it 'returns nil when nothing exists for the source' do
        options[:cache_dir] = make_dir('cache')

        expect(command.send(:find_input_dir, :us)).to be_nil
      end

      it 'keeps the legacy nil for a raw/ dir without dated subdirs' do
        make_dir('data-us', 'raw')
        options[:cache_dir] = make_dir('cache')

        expect(command.send(:find_input_dir, :us)).to be_nil
      end
    end

    context 'with an explicit input_dir option' do
      it 'prefers the per-source subdirectory and its eligible files' do
        input_dir = make_dir('input')
        entity = write_file('input', 'us', 'list', 'deep', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(File.join(input_dir, 'us'))
        expect(files).to eq([entity])
      end

      it 'keeps subdirectory precedence even when it is empty' do
        input_dir = make_dir('input')
        make_dir('input', 'us')
        write_file('input', 'entity.yaml')
        write_file('input', 'uk', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(File.join(input_dir, 'us'))
        expect(files).to eq([])
      end

      it 'does not fall through past an existing but empty path' do
        options[:input_dir] = make_dir('input')
        write_file('data-us', 'processed', 'entity.yaml')

        expect(find_input_dir).to eq(File.join(sources_dir, 'input'))
      end

      it 'never loads deeply nested sibling files from the base dir' do
        input_dir = make_dir('input')
        write_file('input', 'uk', 'deep', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(input_dir)
        expect(files).to eq([])
      end

      it 'keeps the legacy one-level ingestion for the base fallback' do
        input_dir = make_dir('input')
        sibling = write_file('input', 'uk', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(input_dir)
        expect(files).to eq([sibling])
      end

      it 'falls through to auto-detection when the path does not exist' do
        options[:input_dir] = File.join(sources_dir, 'missing')
        write_file('data-us', 'processed', 'entity.yaml')

        expect(find_input_dir)
          .to eq(File.join(sources_dir, 'data-us', 'processed'))
      end
    end

    context 'with non-regular YAML entries' do
      it 'keeps the legacy load-error path for the fallback dir' do
        junk = make_dir('data-us', 'processed', 'not-a-file.yaml')

        dir, files = command.send(:find_input_dir, :us)

        expect(dir).to eq(File.join(sources_dir, 'data-us', 'processed'))
        expect(files).to eq([junk])
      end

      it 'keeps them in the load list of a chosen directory' do
        entity = write_file('data-us', 'processed', 'entity.yaml')
        junk = make_dir('data-us', 'processed', 'broken.yaml')

        dir, files = command.send(:find_input_dir, :us)

        expect(dir).to eq(File.join(sources_dir, 'data-us', 'processed'))
        expect(files).to contain_exactly(entity, junk)
      end

      # The load error is attributed to the file that caused it rather
      # than to the whole source, so the readable files still count and
      # the run fails through the never-exempt per-file gate
      it 'surfaces the load error against the file for a mixed directory' do
        write_file('data-us', 'processed', 'entity.yaml')
        make_dir('data-us', 'processed', 'broken.yaml')

        result = command.send(:harmonize_source, :us)

        expect(result[:status]).to eq(:success)
        expect(result[:errors].first).to match(/broken\.yaml.*directory/i)
      end
    end
  end

  describe '#eligible_yaml_files' do
    def eligible_yaml_files(dir)
      command.send(:eligible_yaml_files, dir)
    end

    it 'collects entities/, flat, and one-level-nested YAML files' do
      dir = make_dir('data-us', 'processed')
      a = write_file('data-us', 'processed', 'entities', 'a.yaml')
      b = write_file('data-us', 'processed', 'b.yml')
      c = write_file('data-us', 'processed', 'list', 'c.yaml')

      expect(eligible_yaml_files(dir)).to eq([a, b, c])
    end

    it 'scans recursively when the direct tiers are empty' do
      dir = make_dir('data-jp', 'sources', 'sanction-lists')
      one = write_file('data-jp', 'sources', 'sanction-lists',
                       'fefta-list', 'entity.yml')
      two = write_file('data-jp', 'sources', 'sanction-lists',
                       'mof-asset-freeze', '01-milosevic', '20260306.yml')

      expect(eligible_yaml_files(dir)).to contain_exactly(one, two)
    end

    it 'excludes deep non-regular entries from the recursive tier' do
      dir = make_dir('data-jp', 'sources', 'sanction-lists')
      deep = write_file('data-jp', 'sources', 'sanction-lists',
                        'list', 'sub', 'entity.yml')
      make_dir('data-jp', 'sources', 'sanction-lists', 'list', 'sub',
               'junk.yaml')

      expect(eligible_yaml_files(dir)).to eq([deep])
    end

    it 'does not scan deeper than one level when direct files exist' do
      dir = make_dir('data-us', 'processed')
      flat = write_file('data-us', 'processed', 'entity.yaml')
      write_file('data-us', 'processed', 'list', 'deep', 'entity.yml')

      expect(eligible_yaml_files(dir)).to eq([flat])
    end

    it 'keeps files reached through a symlinked list directory' do
      dir = make_dir('data-us', 'sources', 'sanction-lists')
      target = write_file('elsewhere', 'entity.yml')
      File.symlink(File.dirname(target), File.join(dir, 'linked'))

      expect(eligible_yaml_files(dir))
        .to eq([File.join(dir, 'linked', 'entity.yml')])
    end

    it 'excludes metadata files at every level' do
      dir = make_dir('data-us', 'sources', 'sanction-lists')
      write_file('data-us', 'sources', 'sanction-lists', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'list',
                 '_index.yml')
      eligible = write_file('data-us', 'sources', 'sanction-lists',
                            'list', 'entity.yml')

      expect(eligible_yaml_files(dir)).to contain_exactly(eligible)
    end

    it 'ignores directories named like YAML files' do
      dir = make_dir('data-us', 'processed')
      make_dir('data-us', 'processed', 'not-a-file.yaml')

      expect(eligible_yaml_files(dir)).to eq([])
    end

    it 'returns each file once despite overlapping patterns' do
      dir = make_dir('data-us', 'processed')
      nested = write_file('data-us', 'processed', 'entities', 'a.yaml')

      expect(eligible_yaml_files(dir)).to eq([nested])
    end

    it 'returns an empty array for nil or missing directories' do
      expect(eligible_yaml_files(nil)).to eq([])
      expect(eligible_yaml_files(File.join(sources_dir, 'missing')))
        .to eq([])
    end
  end

  describe '#harmonize_source' do
    it 'feeds deeply nested sanction-list files to transformation' do
      write_file('data-us', 'processed', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'sdn-list',
                 '2026', 'entity.yml')

      seen = []
      allow(command).to receive(:transform_data) do |src, _data|
        seen << src
        { entity: nil, entry: nil }
      end

      result = command.send(:harmonize_source, :us)

      expect(result[:status]).to eq(:success)
      expect(seen).to eq([:us])
    end
  end
end
