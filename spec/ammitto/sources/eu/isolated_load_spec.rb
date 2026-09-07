# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# `processed_entity.rb` held five classes: `ProcessedAddress`,
# `SimpleNameAlias`, `SimpleBirthdate`, `SimpleSubjectType` and
# `ProcessedEntity`. Splitting turns "these classes share a file, so they
# are always loaded together" into a require graph, and a graph can have a
# missing edge.
#
# This directory is the case where loading proves almost nothing. Of the
# four edges out of `ProcessedEntity`, exactly ONE is resolved when the
# file is read, `attribute :addresses, ProcessedAddress`. The other three
# are named inside method bodies:
#
#   name_aliases  -> SimpleNameAlias      (processed_entity.rb)
#   birthdates    -> SimpleBirthdate
#   subject_type  -> SimpleSubjectType
#
# Ruby does not resolve those until the method runs, so dropping any of
# those three requires leaves a file that loads perfectly and raises
# NameError the first time a transformer touches it. The load-alone sweep
# below cannot see that. The second group of examples is what does.
RSpec.describe 'Ammitto::Sources::Eu model files' do
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

  # Every Lutaml class in the directory, not only the Serializable models.
  # `export_namespace.rb` subclasses `Lutaml::Xml::Namespace` rather than
  # `Lutaml::Model::Serializable`, and a selector keyed on Serializable
  # skipped it while ten files here require it. It did not load alone
  # either, for the same missing `lutaml/model` as the rest.
  #
  # `source.rb` and `transformer.rb` are excluded because neither is a
  # Lutaml class: `source.rb` needs the top-level require for BaseSource.
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/eu/*.rb',
                               __dir__)]
          .select { |f| File.read(f).include?('< Lutaml::') }
          .map { |f| File.basename(f, '.rb') }.sort

  # Fails when a model is added without coverage rather than letting the
  # sweep silently shrink to whatever happens to be on disk.
  it 'covers every model in the directory' do
    expect(files.length).to eq(16)
  end

  files.each do |name|
    it "loads ammitto/sources/eu/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/eu/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # The three run-time edges. Each expression must ENTER the method that
  # names the constant, so the arguments are chosen to get past the guards
  # rather than to be realistic:
  #
  #   name_aliases is `names&.map { ... } || []`, so a nil or empty
  #   `names` returns [] without ever constructing SimpleNameAlias.
  #   birthdates returns [] outright when `birthdate` is nil or empty.
  #
  # Each also asserts on the result. An example that merely called the
  # method and ignored what came back would pass against a version that
  # returned [] for the wrong reason, which is the failure mode the CN
  # spec was rewritten to close.
  {
    'name_aliases names SimpleNameAlias' =>
      'e = Ammitto::Sources::Eu::ProcessedEntity.new(names: ["ACME"]); ' \
      'a = e.name_aliases; ' \
      'raise "no alias built" unless a.length == 1 && a.first.whole_name == "ACME"',
    'birthdates names SimpleBirthdate' =>
      'e = Ammitto::Sources::Eu::ProcessedEntity.new(birthdate: "1970-01-01"); ' \
      'b = e.birthdates; ' \
      'raise "no birthdate built" unless b.length == 1 && b.first.birthdate == "1970-01-01"',
    'subject_type names SimpleSubjectType' =>
      'e = Ammitto::Sources::Eu::ProcessedEntity.new(entity_type: "person"); ' \
      'raise "no subject type built" unless e.subject_type.code == "person"'
  }.each do |what, call|
    it "processed_entity: #{what}, loaded alone" do
      ok, err = load_in_subprocess('ammitto/sources/eu/processed_entity', call)
      expect(ok).to be(true), "processed_entity loaded but failed on use:\n#{err}"
    end
  end
end
