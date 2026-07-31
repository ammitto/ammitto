# frozen_string_literal: true

# The Ruby examples under docs/ named constants that no longer resolve
# (Ammitto::QueryBuilder, Ammitto::Errors::*, Ammitto::SearchIndexExporter) and
# methods that live on the parallel ontology layer rather than the class the
# example named (person?, dissolved?). Nothing executed them, so the rot was
# invisible. This pins the static half of the problem: every Ammitto constant a
# doc mentions must load, and every direct `variable.method` call on a variable
# a block binds with `Ammitto::Klass.new` must exist on that class.
#
# Deliberately narrow. It does NOT execute the examples, so it cannot catch
# undefined locals, wrong argument shapes, or false `# =>` values, and it does
# not follow aliases, safe navigation, chained calls, or setters. The scan is
# textual, so a `variable.method` token inside a comment or string counts too —
# that errs toward checking more than the code runs, never less.
RSpec.describe 'documentation examples' do
  # Deliberately a method, not a constant: a constant assigned here would leak
  # into Object and could collide with another spec.
  def self.docs_dir
    File.expand_path('../../docs', __dir__)
  end

  def self.adoc_files
    Dir.glob("#{docs_dir}/**/*.adoc")
  end

  def self.relative(file)
    file.sub("#{File.dirname(docs_dir)}/", '')
  end

  # A constant is fair game only once the docs' own `require` lines have run —
  # SearchIndexExporter is not autoloaded by `require "ammitto"`, and the docs
  # tell the reader to require it explicitly. These are pooled across all
  # pages, so this does not prove any single page requires what it uses.
  adoc_files.each do |file|
    File.read(file).scan(%r{^\s*require ['"](ammitto/[\w/]+)['"]}) do |(lib)|
      require lib
    end
  end

  # Every `Ammitto::Foo` token the docs mention, with where it was found.
  def self.constant_references
    refs = Hash.new { |hash, key| hash[key] = [] }
    adoc_files.each do |file|
      File.readlines(file).each_with_index do |line, index|
        line.scan(/\bAmmitto(?:::[A-Z]\w*)+/) do |const|
          refs[const] << "#{relative(file)}:#{index + 1}"
        end
      end
    end
    refs
  end

  # Each variable a Ruby block binds with `Ammitto::Klass.new` — every such
  # binding, not just the first — paired with the direct `variable.method`
  # calls the block makes on it. Scanning only the first binding would let a
  # later receiver (`serializer = ...`) rot unnoticed.
  def self.receiver_calls
    found = []
    adoc_files.each do |file|
      File.read(file).scan(/\[source,\s*ruby\]\n-{4,}\n(.*?)\n-{4,}/m) do |(code)|
        code.scan(/^\s*(\w+)\s*=\s*(Ammitto(?:::\w+)*)\.new\b/) do |var, klass|
          methods = code.scan(/\b#{Regexp.escape(var)}\.([a-z_]+[?!]?)/)
                        .flatten.uniq
          found << [relative(file), klass, methods] unless methods.empty?
        end
      end
    end
    found
  end

  # Every keyword the docs hand to `Ammitto.search`, with where it appears.
  #
  # A wrong option here does not raise: QueryBuilder takes an options hash
  # and reads the keys it knows, so an unknown one is accepted and dropped.
  # The example still runs, and the page still claims it filtered
  # something. Two pages documented `entity_type:` that way for as long as
  # nothing executed them, and executing them would not have caught it
  # either — only comparing the keyword against the reader does.
  def self.search_option_references
    refs = Hash.new { |hash, key| hash[key] = [] }
    adoc_files.each do |file|
      File.read(file).scan(/\bAmmitto\.search\((.*?)\)/m) do |(args)|
        args.scan(/(\w+):/) { |(key)| refs[key] << relative(file) }
      end
    end
    refs
  end

  # The option keys QueryBuilder actually reads, taken from its source
  # rather than restated here, so this cannot drift out of date without
  # the class itself changing.
  def self.search_options_read
    source = File.read(
      File.expand_path('../../lib/ammitto/search/query_builder.rb', __dir__)
    )
    source.scan(/options\[:(\w+)\]/).flatten.uniq
  end

  files = adoc_files
  references = constant_references
  receivers = receiver_calls
  search_options = search_option_references
  honoured = search_options_read

  it 'reads the option keys QueryBuilder honours' do
    expect(honoured).to include('sources', 'limit', 'offset')
  end

  search_options.sort.each do |option, locations|
    it "passes #{option}: to Ammitto.search, which reads it " \
       "(#{locations.uniq.join(', ')})" do
      expect(honoured).to include(option)
    end
  end

  # Guards the generators themselves. Without these, a docs move or a regex
  # that quietly stops matching would leave the suite green while checking
  # nothing — the exact failure mode that let the original rot through.
  it 'finds Ruby examples to check' do
    expect(files).not_to be_empty
    expect(references).not_to be_empty
    expect(receivers).not_to be_empty
  end

  # Per-file rather than aggregate, so one file dropping out of the scan is
  # not masked by the others. It proves the file was scanned and yielded at
  # least one constant — not that every block in it was parsed.
  adoc_files.each do |file|
    next unless File.read(file).match?(/\bAmmitto::[A-Z]/)

    prefix = "#{relative(file)}:"
    it "collects the constants mentioned in #{relative(file)}" do
      found = references.select do |_, locations|
        locations.any? { |location| location.start_with?(prefix) }
      end
      expect(found).not_to be_empty
    end
  end

  references.sort.each do |const, locations|
    it "resolves #{const} (#{locations.first})" do
      expect { Object.const_get(const) }.not_to raise_error
    end
  end

  receivers.each do |file, klass, methods|
    it "defines #{methods.size} documented method(s) on #{klass} (#{file})" do
      defined_methods = Object.const_get(klass).instance_methods
      expect(methods.reject { |m| defined_methods.include?(m.to_sym) })
        .to be_empty
    end
  end
end
