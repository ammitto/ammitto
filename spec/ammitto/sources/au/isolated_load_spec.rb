# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# `sanctions_list.rb` held all fourteen definitions: five enumeration
# modules, seven models, a base class and the collection. Splitting turns
# "these share a file, so they are always loaded together" into a require
# graph, and a graph can have a missing edge.
#
# This directory is the strongest case in the series for not trusting a
# load-alone sweep. An AST scan of the original file finds that most of the
# edges out of these definitions are named inside method bodies, where Ruby
# does not resolve them until the method runs:
#
#   Name           -> AliasStrength, NameType, Script   (run time only)
#   Sanction       -> EffectType                        (run time only)
#   BaseEntity     -> Name, Sanction                    (both)
#   Individual     -> FlexibleDate, Location            (both)
#   SanctionsList  -> EntityType                        (run time only)
#
# `Name` and `Sanction` have NO read-time reference to the enumerations they
# depend on. Requiring either alone succeeds with any one of those requires
# deleted. Where it then raises differs: a missing `Name` dependency raises
# while a name is parsed, but a missing `EffectType` parses a whole row
# happily and raises only when `Sanction#effects` is called. The second
# group of examples is what closes both.
RSpec.describe 'Ammitto::Sources::Au model files' do
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

  # Named exclusions rather than a grep for a superclass. Three of these
  # models subclass `BaseEntity` rather than Lutaml directly, and five are
  # plain modules with no superclass at all, so any grep keyed on `Lutaml`
  # would drop them silently. Naming what is NOT a model fails loudly when
  # something new appears instead.
  non_models = %w[source transformer].freeze
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/au/*.rb',
                               __dir__)]
          .map { |f| File.basename(f, '.rb') }
          .reject { |name| non_models.include?(name) }
          .sort

  it 'covers every definition in the directory' do
    expect(files.length).to eq(14)
  end

  files.each do |name|
    it "loads ammitto/sources/au/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/au/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # The run-time edges, each entered rather than merely loaded, and each
  # asserting on what came back. An example that called the method and
  # ignored the result would pass against a version that returned nothing
  # for the wrong reason.
  #
  # `Name.from_csv` reaches all three of its enumerations in one call, so
  # deleting any one of the three fails this example. Not this one alone:
  # the collection example below parses names too, and fails with it.
  it 'name reaches its three enumerations, loaded alone' do
    call = 'n = Ammitto::Sources::Au::Name.from_csv("Mohammad Salah JOKAR", ' \
           '"Alias", "Strong"); ' \
           'raise "name_type"     unless n.name_type == "Alias"; ' \
           'raise "alias_strength" unless n.alias_strength == "Strong"; ' \
           'raise "script"        unless n.script'
    ok, err = load_in_subprocess('ammitto/sources/au/name', call)
    expect(ok).to be(true), "name loaded but failed on use:\n#{err}"
  end

  # `#effects` names EffectType only inside the branches, so every flag has
  # to be true to reach all four; an all-false Sanction returns [] without
  # ever naming the constant.
  it 'sanction reaches EffectType, loaded alone' do
    call = 's = Ammitto::Sources::Au::Sanction.new(' \
           'targeted_financial_sanction: true, travel_ban: true, ' \
           'arms_embargo: true, maritime_restriction: true); ' \
           'raise "effects" unless s.effects.length == 4'
    ok, err = load_in_subprocess('ammitto/sources/au/sanction', call)
    expect(ok).to be(true), "sanction loaded but failed on use:\n#{err}"
  end

  # The collection parses a real row shape, which is the only path that
  # reaches EntityType and, through the entities it builds, BaseEntity's
  # `merge_row` and `build_sanction` and Individual's date and location
  # handling. Three rows share one base reference so the merge path runs.
  it 'sanctions_list parses all three entity types, loaded alone' do
    header = 'Reference,Name of Individual or Entity,Type,Name Type,' \
             'Alias Strength,Date of Birth,Place of Birth,Citizenship,' \
             'Address,Additional Information,Listing Information,' \
             'IMO Number,Committees,Control Date,' \
             'Instrument of Designation,Targeted Financial Sanction,' \
             'Travel Ban,Arms Embargo,Maritime Restriction'
    rows = [
      '8577,Mohammad Salah JOKAR,Individual,Primary Name,,5 May 1957,Yazd,' \
      'Iranian,,,Autonomous Sanctions List 2012,,Autonomous (Iran),2/2/26,' \
      'Amendment Instrument 2026,TRUE,TRUE,FALSE,FALSE',
      '8577b,Mohammad Saleh JOKAR,Individual,Alias,Strong,5 May 1957,Yazd,' \
      'Iranian,,,Autonomous Sanctions List 2012,,Autonomous (Iran),2/2/26,' \
      'Amendment Instrument 2026,TRUE,TRUE,FALSE,FALSE',
      '8556,SAFETY EQUIPMENT PROCUREMENT,Entity,Primary Name,,,,,,,' \
      'Listed by 1737 Committee,,1737 (Iran),12/12/25,' \
      'Charter Regulations 2025,TRUE,FALSE,FALSE,FALSE',
      '8230,MOCHA,Vessel,Primary Name,,,,,,,Designated vessel,9271951,' \
      'Autonomous (Vessels),6/18/25,Vessel Designation 2025,FALSE,FALSE,' \
      'FALSE,TRUE'
    ]
    csv  = ([header] + rows).join('\n')
    call = "l = Ammitto::Sources::Au::SanctionsList.from_csv(\"#{csv}\\n\"); " \
           'raise "individuals" unless l.individuals.length == 1; ' \
           'raise "organizations" unless l.organizations.length == 1; ' \
           'raise "vessels" unless l.vessels.length == 1; ' \
           'raise "merge_row" unless l.individuals.first.names.length == 2'
    ok, err = load_in_subprocess('ammitto/sources/au/sanctions_list', call)
    expect(ok).to be(true), "sanctions_list loaded but failed on use:\n#{err}"
  end
end
