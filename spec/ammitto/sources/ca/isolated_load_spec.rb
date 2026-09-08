# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# `sanctions_list.rb` held `Record` and `SanctionsList`. Splitting turns
# "these share a file, so they are always loaded together" into a require
# graph, and a graph can have a missing edge.
#
# `SanctionsList` names `Record` once, in `attribute :records, Record`, which
# resolves when the file is read. So the load-alone sweep below is sufficient
# for this directory; there is no run-time edge needing a second group of
# examples, unlike `au`, `eu` and `un_vessels`.
RSpec.describe 'Ammitto::Sources::Ca model files' do
  # Loading in-process would prove nothing: RSpec has already required the
  # whole tree by the time an example runs.
  # Returns [ok, stderr]. Keeping stderr matters: a missing require fails
  # with a NameError naming the constant, and discarding it leaves the
  # failure message as a bare "expected true, got false".
  def load_in_subprocess(path)
    lib = File.expand_path('../../../../lib', __dir__)
    err = Tempfile.new('isolated_load')
    ok = system(RbConfig.ruby, '-I', lib, '-e', "require '#{path}'",
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
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/ca/*.rb',
                               __dir__)]
          .map { |f| File.basename(f, '.rb') }
          .reject { |name| non_models.include?(name) }
          .sort

  it 'covers every model file in the directory' do
    expect(files).to eq(%w[record sanctions_list])
  end

  files.each do |name|
    it "loads ammitto/sources/ca/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/ca/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end
end
