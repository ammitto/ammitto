# frozen_string_literal: true

# The Ruby examples under docs/ named constants that no longer resolve
# (Ammitto::QueryBuilder, Ammitto::Errors::*, Ammitto::SearchIndexExporter) and
# methods that live on the parallel ontology layer rather than the class the
# example named (person?, dissolved?). Nothing executed them, so the rot was
# invisible. This pins the static half of the problem: every Ammitto constant a
# doc mentions must load, and every direct `variable.method` call on a variable
# a block binds with `Ammitto::Klass.new` must exist on that class.
#
# Those scans read the examples as text, which is why they once passed four
# blocks that Ruby cannot even parse: reference/entity-types.adoc wrote
# `Ammitto::PersonEntity.new(...)` and three siblings, and `...` is argument
# forwarding, illegal outside a forwarding method. The textual scan saw a
# `Klass.new` binding and a list of methods and approved them. So every block
# is now compiled as well — a page that does not parse fails here.
#
# Still narrow. Compiling is not running: it cannot catch undefined locals,
# wrong argument shapes, or false `# =>` values. The `variable.method` scan is
# textual, so such a token inside a comment or string counts too — that errs
# toward checking more than the code runs, never less.
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

  # Every Ruby example the docs publish, as [file, starting line, source].
  # One extractor for both the textual scans and the compile gate, so the two
  # can never disagree about which blocks exist.
  def self.ruby_blocks
    adoc_files.flat_map do |file|
      text = File.read(file)
      blocks = []
      text.scan(/\[source,\s*ruby\]\n-{4,}\n(.*?)\n-{4,}/m) do |(code)|
        line = text[0...Regexp.last_match.begin(1)].count("\n") + 1
        blocks << [relative(file), line, code]
      end
      blocks
    end
  end

  # How many Ruby examples the docs declare, counted from the block headers
  # rather than from the extractor. The two are compared below: without that,
  # an extractor regex that quietly stopped matching would generate no
  # examples at all and leave the suite green.
  def self.declared_block_count
    adoc_files.sum { |file| File.read(file).scan(/^\[source,\s*ruby\]$/).size }
  end

  # Each variable a Ruby block binds with `Ammitto::Klass.new` — every such
  # binding, not just the first — paired with the direct `variable.method`
  # calls the block makes on it. Scanning only the first binding would let a
  # later receiver (`serializer = ...`) rot unnoticed.
  def self.receiver_calls
    ruby_blocks.flat_map do |file, _line, code|
      found = []
      code.scan(/^\s*(\w+)\s*=\s*(Ammitto(?:::\w+)*)\.new\b/) do |var, klass|
        methods = code.scan(/\b#{Regexp.escape(var)}\.([a-z_]+[?!]?)/)
                      .flatten.uniq
        found << [file, klass, methods] unless methods.empty?
      end
      found
    end
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
  blocks = ruby_blocks
  declared = declared_block_count
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

  # Counted from the `[source,ruby]` headers, so the compile gate below cannot
  # silently shrink to nothing: drop a block from the extractor and this fails
  # before the missing example can be mistaken for a passing one.
  it 'extracts every Ruby example the docs declare' do
    expect(blocks.size).to eq(declared)
    expect(declared).to be_positive
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

  # The gate the textual scans above cannot be: an example a reader pastes
  # into Ruby has to at least parse. Compiling stops short of running it, so
  # nothing here reaches the network, the cache, or the filesystem. The file
  # and line handed to `compile` are the doc's own, so a failure names the
  # page and line to open rather than an offset into an extracted string.
  blocks.each do |file, line, code|
    it "parses the Ruby example at #{file}:#{line}" do
      error = nil
      begin
        RubyVM::InstructionSequence.compile(code, file, file, line)
      rescue SyntaxError => e
        error = e.message
      end
      expect(error).to be_nil
    end
  end
end
