# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# The CN models were split from four multi-class files into one file per
# class. Splitting turns what used to be "these classes share a file, so
# they are always loaded together" into a require graph, and a graph can
# have a missing edge. It had one: `OrganizationEntry` declares
# `attribute :name, LocalizedNameEntry` and the two classes had lived in
# different files all along, so requiring `organizations_source` alone
# raised NameError. Nothing caught it, because every spec and the
# harmonizer reach these models through a file that happens to load the
# rest first.
#
# Each example loads one file in a fresh process. A missing require fails
# here and only here.
RSpec.describe 'Ammitto::Sources::Cn model files' do
  # Loading in-process would prove nothing: RSpec has already required
  # the whole tree by the time an example runs.
  # Returns [ok, stderr]. Keeping stderr matters: a missing require fails
  # with a NameError naming the constant, and discarding it left the
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

  # The Lutaml model files only. `source.rb` and `transformer.rb` inherit
  # from BaseSource and BaseTransformer, which the top-level `ammitto`
  # require provides; neither has ever loaded on its own and this change
  # did not alter that. `reference_docs_parser.rb` is a plain class and
  # does load alone, but it is not a model either.
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/cn/*.rb',
                               __dir__)]
          .select { |f| File.read(f).include?('Lutaml::Model::Serializable') }
          .map { |f| File.basename(f, '.rb') }.sort

  it 'covers every model in the directory' do
    expect(files.length).to eq(18)
  end

  files.each do |name|
    it "loads ammitto/sources/cn/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/cn/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # Loading is not enough. These models reference Ammitto::Ontology classes
  # from inside method bodies, which Ruby does not resolve until the method
  # runs — so a file could load cleanly and raise NameError on first use.
  # That was true here: three files constructed Ontology classes without
  # requiring them, on this branch and on main before it.
  {
    'localized_name_entry' => 'Ammitto::Sources::Cn::LocalizedNameEntry.new(en: "x").to_localized_strings',
    'document_type_entry' => 'Ammitto::Sources::Cn::DocumentTypeEntry.new',
    'organization_entry' => 'Ammitto::Sources::Cn::OrganizationEntry.new'
  }.each do |name, call|
    it "#{name} resolves the Ontology constants it names, loaded alone" do
      ok, err = load_in_subprocess("ammitto/sources/cn/#{name}", call)
      expect(ok).to be(true), "#{name} loaded but failed on use:\n#{err}"
    end
  end
end
