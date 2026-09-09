# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# `vessel.rb` held `NameVariant` and `Vessel`. Splitting turns "these share a
# file, so they are always loaded together" into a require graph, and a graph
# can have a missing edge.
#
# `Vessel` names `NameVariant` twice, and the two are different kinds of edge:
#
#   attribute :names, NameVariant     resolved when the file is read
#   NameVariant.from(:hash, name)     inside .from_hash, at run time
#
# Named rather than cited by line, because line numbers in a comment go stale
# on the next edit. These two did: they were written against the file before
# the split.
#
# The read-time one is caught by loading the file. The run-time one is not,
# and would raise the first time a harvested vessel was parsed. The second
# example is for that.
RSpec.describe 'Ammitto::Sources::UnVessels model files' do
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

  # Named exclusions rather than a grep for a superclass. A model that
  # subclasses another model would not match such a grep and would drop out
  # of coverage silently; naming what is NOT a model fails loudly when
  # something new appears.
  non_models = %w[source transformer].freeze
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/un_vessels/*.rb',
                               __dir__)]
          .map { |f| File.basename(f, '.rb') }
          .reject { |name| non_models.include?(name) }
          .sort

  it 'covers every model file in the directory' do
    expect(files).to eq(%w[name_variant sanctions_list vessel])
  end

  files.each do |name|
    it "loads ammitto/sources/un_vessels/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/un_vessels/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # The run-time edge. `.from_hash` maps over `data['names']`, so the hash
  # has to carry a non-empty one to reach `NameVariant.from`: an empty or
  # missing list maps zero times and never names the constant. Asserting on
  # the built object rather than on the call completing is what stops this
  # passing against a version that quietly produced nothing.
  it 'vessel builds NameVariant at run time, loaded alone' do
    call = 'v = Ammitto::Sources::UnVessels::Vessel.from_hash(' \
           '"id" => "V1", "names" => [{ "full_name" => "MOCHA" }]); ' \
           'raise "no name built" unless v.names.length == 1 && ' \
           'v.names.first.full_name == "MOCHA"'
    ok, err = load_in_subprocess('ammitto/sources/un_vessels/vessel', call)
    expect(ok).to be(true), "vessel loaded but failed on use:\n#{err}"
  end
end
