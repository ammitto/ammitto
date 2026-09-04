# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# The CH models were split from one 285-line file holding ten classes into
# one file per class. Splitting turns "these classes share a file, so they
# are always loaded together" into a require graph, and a graph can have a
# missing edge: `Identity` declares `attribute :names, Name`, and that is
# evaluated when the file is read, so a missing require is a NameError the
# moment the file is loaded by itself.
#
# Nothing else would catch it. Every spec and the harmonizer reach these
# models through `sources/ch.rb`, which requires the whole directory in an
# order that happens to work.
#
# Each example loads one file in a fresh process. A missing require fails
# here and only here.
#
# Unlike the CN models, none of these name a constant from another
# namespace inside a method body, so loading is the whole test. If one ever
# does, this file needs the CN treatment: an example that CALLS the method,
# because Ruby does not resolve a constant in a method body until it runs.
RSpec.describe 'Ammitto::Sources::Ch model files' do
  # Loading in-process would prove nothing: RSpec has already required the
  # whole tree by the time an example runs. Keeping stderr matters — a
  # missing require fails with a NameError naming the constant, and
  # discarding it leaves the failure as a bare "expected true, got false".
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

  # The Lutaml model files only. `source.rb` and `transformer.rb` inherit
  # from BaseSource and BaseTransformer, which the top-level `ammitto`
  # require provides; neither has ever loaded on its own and this split
  # does not change that.
  files = %w[
    address
    day_month_year
    entity
    identity
    individual
    name
    name_part
    sanctions_list
    sanctions_program
    target
  ]

  it 'covers every model file in the directory' do
    on_disk = Dir[File.expand_path('../../../../lib/ammitto/sources/ch/*.rb',
                                   __dir__)]
              .map { |p| File.basename(p, '.rb') }
              .reject { |n| %w[source transformer].include?(n) }

    expect(on_disk.sort).to eq(files.sort)
  end

  files.each do |name|
    it "loads ammitto/sources/ch/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/ch/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end
end
