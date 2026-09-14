# frozen_string_literal: true

require 'spec_helper'

# Every model file must stand up on its own.
#
# `processed_entity.rb` held five classes: `ProcessedAddress`,
# `SimpleNameAlias`, `SimpleBirthdate`, `SimpleSubjectType` and
# `ProcessedEntity`. Splitting turns "these classes share a file, so they
# are always loaded together" into a require graph, and a graph can have a
# missing edge.
#
# Every edge remaining in this directory is resolved when the file is read,
# so the sweep below is sufficient. That was not true while
# `processed_entity.rb` was here: three of its four edges were named inside
# method bodies and needed examples that entered them. That file and its
# four support classes are gone, having turned out to be unreachable.
RSpec.describe 'Ammitto::Sources::Eu model files' do
  include IsolatedLoadHelper

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
    expect(files.length).to eq(11)
  end

  files.each do |name|
    it "loads ammitto/sources/eu/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/eu/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end
end
