# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# The UK models were split from two multi-class files into one file per
# class: `designation.rb` held NamesWrapper, NonLatinNamesWrapper,
# AddressesWrapper and Designation, and `individual_details.rb` held
# Location, BirthDetails and IndividualDetails. Splitting turns "these
# classes share a file, so they are always loaded together" into a require
# graph, and a graph can have a missing edge.
#
# Every REQUIRE edge here is resolved when the file is read, not when a
# method runs: `attribute :items, Name` names its class at definition time,
# so a missing require fails the load-alone example below rather than
# hiding until first use. The `include` edges are different and the second
# group of examples exists for them.
#
# Each example loads one file in a fresh process. Nothing else catches
# this: every spec and the harmonizer reach these models through a file
# that happens to load the rest first.
RSpec.describe 'Ammitto::Sources::Uk model files' do
  # Loading in-process would prove nothing: RSpec has already required the
  # whole tree by the time an example runs.
  # Returns [ok, stderr]. Keeping stderr matters: a missing require fails
  # with a NameError naming the constant, and discarding it leaves the
  # failure message as a bare "expected true, got false".
  def load_in_subprocess(path, and_then = nil)
    lib = File.expand_path('../../../../lib', __dir__)
    script = and_then ? "require '#{path}'; #{and_then}" : "require '#{path}'"
    err = Tempfile.new('isolated_load')
    ok = system(RbConfig.ruby, '-I', lib, '-e', script,
                out: File::NULL, err: err.path)
    [ok, File.read(err.path)]
  ensure
    err&.close
    err&.unlink
  end

  # The Lutaml model files only. Neither `source.rb` nor `transformer.rb` is
  # a model, and they differ: `transformer.rb` requires its own base at
  # line 3 and does load alone, while `source.rb` relies on the top-level
  # `ammitto` require for BaseSource and does not. `date_normalizer.rb` is
  # a plain module, exercised through the three models that include it.
  # Named exclusions rather than a grep for a superclass. A model that
  # subclasses another model rather than Lutaml directly would not match
  # such a grep, and would drop out of this sweep silently; naming what is
  # NOT a model fails loudly instead when something new appears.
  non_models = %w[date_normalizer source transformer].freeze
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/uk/*.rb',
                               __dir__)]
          .map { |f| File.basename(f, '.rb') }
          .reject { |name| non_models.include?(name) }
          .sort

  # Fails when a model is added without coverage rather than letting the
  # sweep silently shrink to whatever happens to be on disk.
  it 'covers every model-bearing file in the directory' do
    expect(files.length).to eq(12)
  end

  files.each do |name|
    it "loads ammitto/sources/uk/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/uk/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # Loading is not enough for the three files that `include DateNormalizer`,
  # and the sweep above cannot stand in for these. Deleting an `include` is
  # not a missing require: the file still loads clean, and the method is
  # simply absent when something calls it. Measured on `designations.rb`:
  # without its include the load-alone example still passes and only the
  # call raises.
  #
  # These examples also cover a gap the sweep leaves. `designation.rb`
  # requires `date_normalizer` directly, but `individual_details` supplies
  # it transitively, so deleting that require breaks nothing here. What is
  # under test is that `normalize_date` reaches the caller, not which file
  # declared the dependency.
  #
  # So the call has to ENTER the method. Reading the attribute back is what
  # does it: `Designation#last_updated`, `Designations#date_generated` and
  # `IndividualDetails#dobs` are all overrides, not plain readers.
  #
  # The arguments are chosen to reach the conversion rather than return
  # early: `normalized_dobs` returns [] when @dobs is nil, which would
  # never touch DateNormalizer.
  {
    'designation' =>
      'raise "not normalized" unless Ammitto::Sources::Uk::Designation' \
      '.new(last_updated: "01/01/2020").last_updated == "2020-01-01"',
    'designations' =>
      'raise "not normalized" unless Ammitto::Sources::Uk::Designations' \
      '.new(date_generated: "01/01/2020").date_generated == "2020-01-01"',
    'individual_details' =>
      'raise "not normalized" unless Ammitto::Sources::Uk::IndividualDetails' \
      '.new(dobs: ["01/01/2020"]).dobs == ["2020-01-01"]'
  }.each do |name, call|
    it "#{name} normalizes dates through DateNormalizer, loaded alone" do
      ok, err = load_in_subprocess("ammitto/sources/uk/#{name}", call)
      expect(ok).to be(true), "#{name} loaded but failed on use:\n#{err}"
    end
  end
end
