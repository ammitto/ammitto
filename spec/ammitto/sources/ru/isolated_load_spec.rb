# frozen_string_literal: true

require 'spec_helper'

# Every model file must stand up on its own.
#
# `sanctions_list.rb` held `SanctionedEntity`, the flat announcement (now
# `ListAnnouncement`) and `SanctionsList`. Splitting turns "these classes share a file, so they are
# always loaded together" into a require graph, and a graph can have a
# missing edge.
#
# `ListAnnouncement` names `SanctionedEntity` twice, and the two are not
# the same kind of edge. `attribute :entities, SanctionedEntity` in
# `list_announcement.rb` resolves when the file is read, so the load-alone
# sweep below catches a missing require. `SanctionedEntity.new` inside
# `.from_parsed_data` does not resolve until that method runs, and no
# amount of loading will reveal it. The second group of examples is for
# that one.
RSpec.describe 'Ammitto::Sources::Ru model files' do
  include IsolatedLoadHelper

  # The models this file covers, named rather than discovered. A grep for
  # `< Lutaml::` would omit an indirect subclass or a differently formatted
  # declaration while the count stayed the same, so the guard would be
  # weaker than it looks. Comparing the named list against what is actually
  # on disk fails loudly when a model is added or renamed.
  files = %w[announcement announcement_block announcement_transformer entity
             instrument list_announcement lost_party_guard measure
             sanction_details sanctioned_entity sanctions_list].freeze

  it 'covers every model file in the directory' do
    on_disk = Dir[File.expand_path('../../../../lib/ammitto/sources/ru/*.rb',
                                   __dir__)]
              .map { |f| File.basename(f, '.rb') }
              .reject { |name| %w[source transformer].include?(name) }
              .sort

    expect(on_disk).to eq(files.sort)
  end

  files.each do |name|
    it "loads ammitto/sources/ru/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/ru/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # The run-time edge. `.from_parsed_data` builds a `SanctionedEntity` per
  # element of `data[:entities]`, so the call has to pass a non-empty list
  # to reach the constructor: an empty or missing one iterates zero times
  # and never names the constant. Asserting on the built entity rather
  # than on the call completing is what stops this passing against a
  # version that quietly produced nothing.
  it 'list_announcement builds SanctionedEntity at run time, loaded alone' do
    call = 'a = Ammitto::Sources::Ru::ListAnnouncement.from_parsed_data(' \
           'number: "1", entities: [{ russian_name: "Иванов", ' \
           'english_name: "Ivanov" }]); ' \
           'raise "no entity built" unless a.entities.length == 1 && ' \
           'a.entities.first.english_name == "Ivanov"'
    ok, err = load_in_subprocess('ammitto/sources/ru/list_announcement', call)
    expect(ok).to be(true), "list_announcement loaded but failed on use:\n#{err}"
  end
end
