# frozen_string_literal: true

# The Ruby examples under docs/ named constants that no longer resolve
# (Ammitto::QueryBuilder, Ammitto::Errors::*, Ammitto::SearchIndexExporter).
# Nothing executed them, so the rot was invisible. This pins the cheap half of
# the problem: every Ammitto constant a doc mentions must actually load.
RSpec.describe 'documentation examples' do
  docs_dir = File.expand_path('../../docs', __dir__)

  # A constant is fair game only once the docs' own `require` lines have run —
  # SearchIndexExporter is not autoloaded by `require "ammitto"`, and the docs
  # tell the reader to require it explicitly.
  before(:all) do
    Dir.glob("#{docs_dir}/**/*.adoc").each do |file|
      File.read(file).scan(%r{^\s*require ['"](ammitto/[\w/]+)['"]}) do |(lib)|
        require lib
      end
    end
  end

  def self.constant_references(docs_dir)
    refs = Hash.new { |hash, key| hash[key] = [] }
    Dir.glob("#{docs_dir}/**/*.adoc").each do |file|
      relative = file.sub("#{File.dirname(docs_dir)}/", '')
      File.readlines(file).each_with_index do |line, index|
        line.scan(/\bAmmitto(?:::[A-Z]\w*)+/) do |const|
          refs[const] << "#{relative}:#{index + 1}"
        end
      end
    end
    refs
  end

  references = constant_references(docs_dir)

  it 'references at least one Ammitto constant' do
    expect(references).not_to be_empty
  end

  references.sort.each do |const, locations|
    it "resolves #{const} (#{locations.first})" do
      expect { Object.const_get(const) }.not_to raise_error
    end
  end
end
