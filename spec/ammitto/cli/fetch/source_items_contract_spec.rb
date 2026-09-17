# frozen_string_literal: true

require 'ammitto'

# `ItemMapper#items_from_data` (see item_mapper_spec.rb) trusts every
# fetchable source's parsed root class to answer `#items` with an array,
# never nil — that's the whole contract `items_from_data` now delegates
# to instead of a 15-branch case statement.
#
# Adding `#items` by copying each source's existing `all_entities` /
# `all_identities` / `all_vessels` helper verbatim looked safe and wasn't:
# `au`, `ch`, `jp` and `un_vessels`'s helpers read their underlying
# attribute directly with no `|| []` guard, so a bare `.new` (before any
# attribute is assigned — exactly the state a source-model class is in
# for one moment during `.from_xml`/`.from_csv`/`.from_xlsx` construction,
# and always the state in a test double) either raised (`au`, via `nil +
# nil`) or returned nil outright (`ch`, `jp`, `un_vessels`), where the
# `case`-statement version this replaced always fell back to `[]` because
# every one of its branches read `data.<attr> || []`. Both failure shapes
# are checked here, on every fetchable source, not just the four that
# were actually wrong.
RSpec.describe 'fetchable source classes\' #items contract' do
  {
    uk: -> { Ammitto::Sources::Uk::Designations },
    eu: -> { Ammitto::Sources::Eu::Export },
    un: -> { Ammitto::Sources::Un::ConsolidatedList },
    us: -> { Ammitto::Sources::Us::SdnList },
    wb: -> { Ammitto::Sources::Wb::Response },
    au: -> { Ammitto::Sources::Au::SanctionsList },
    ca: -> { Ammitto::Sources::Ca::SanctionsList },
    ch: -> { Ammitto::Sources::Ch::SanctionsList },
    tr: -> { Ammitto::Sources::Tr::SanctionsList },
    nz: -> { Ammitto::Sources::Nz::SanctionsList },
    eu_vessels: -> { Ammitto::Sources::EuVessels::SanctionsList },
    jp: -> { Ammitto::Sources::Jp::SanctionsList },
    un_vessels: -> { Ammitto::Sources::UnVessels::SanctionsList }
  }.each do |source, klass_thunk|
    it "#{source}: #items never raises and never returns nil on an empty instance" do
      klass = klass_thunk.call

      items = klass.new.items

      expect(items).to eq([])
    end
  end
end
