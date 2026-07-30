# frozen_string_literal: true

# The Ruby examples under docs/ named constants that no longer resolve
# (Ammitto::QueryBuilder, Ammitto::Errors::*, Ammitto::SearchIndexExporter) and
# methods that live on the parallel ontology layer rather than the class the
# example named (person?, dissolved?). Nothing executed them, so the rot was
# invisible. This pins the static half of the problem: every Ammitto constant a
# doc mentions must load, and every method called on a documented constructor's
# receiver must exist on that class.
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
  # tell the reader to require it explicitly.
  before(:all) do
    self.class.adoc_files.each do |file|
      File.read(file).scan(%r{^\s*require ['"](ammitto/[\w/]+)['"]}) do |(lib)|
        require lib
      end
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

  # Ruby blocks that bind a variable to a documented constructor, paired with
  # every method the block then calls on that variable.
  def self.receiver_calls
    found = []
    adoc_files.each do |file|
      File.read(file).scan(/\[source,\s*ruby\]\n-{4,}\n(.*?)\n-{4,}/m) do |(code)|
        next unless code =~ /^\s*(\w+)\s*=\s*(Ammitto(?:::\w+)*)\.new\b/

        var = Regexp.last_match(1)
        klass = Regexp.last_match(2)
        methods = code.scan(/^\s*#{Regexp.escape(var)}\.([a-z_]+[?!]?)/)
                      .flatten.uniq
        found << [relative(file), klass, methods] unless methods.empty?
      end
    end
    found
  end

  files = adoc_files
  references = constant_references
  receivers = receiver_calls

  # Guards the generators themselves. Without these, a docs move or a regex
  # that quietly stops matching would leave the suite green while checking
  # nothing — the exact failure mode that let the original rot through.
  it 'finds Ruby examples to check' do
    expect(files).not_to be_empty
    expect(references).not_to be_empty
    expect(receivers).not_to be_empty
  end

  # Per-file, not just aggregate: losing coverage of ONE file must fail.
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
