# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Every model file must stand up on its own.
#
# `sanctions_list.rb` was 1,070 lines holding `IntegrityError`,
# `SanctionedEntity` and `SanctionsList`. Splitting turns "these share a file,
# so they are always loaded together" into a require graph, and a graph can
# have a missing edge.
#
# Three of `SanctionsList`'s four edges are run-time only, which is why the
# second group of examples exists:
#
#   attribute :entities, SanctionedEntity      read time
#   raise IntegrityError                       inside .header_fields
#   SanctionedEntity.exact_integer_text        inside .read_row
#   Utils::IriSanitizer.sanitize               inside .verify_reservations!
#
# The last of those is to a file OUTSIDE this directory, and the split
# dropped its require: `sanctions_list.rb` carried
# `require_relative '../../utils/iri_sanitizer'` before the split and does
# again now. It survived only because the new `sanctioned_entity.rb` happens
# to require the same file, so the edge was real and invisible at once.
#
# Dropping either run-time require leaves a file that loads perfectly and
# fails the first time a workbook is parsed. The load-alone sweep cannot see
# that.
RSpec.describe 'Ammitto::Sources::Tr model files' do
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

  # Named exclusions rather than a grep for a superclass. `IntegrityError`
  # subclasses `StandardError`, not Lutaml, so any grep keyed on Lutaml would
  # drop it silently while the count still looked right.
  non_models = %w[source transformer].freeze
  files = Dir[File.expand_path('../../../../lib/ammitto/sources/tr/*.rb',
                               __dir__)]
          .map { |f| File.basename(f, '.rb') }
          .reject { |name| non_models.include?(name) }
          .sort

  it 'covers every model file in the directory' do
    expect(files).to eq(%w[integrity_error sanctioned_entity sanctions_list])
  end

  files.each do |name|
    it "loads ammitto/sources/tr/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/sources/tr/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end

  # `Entity` is an alias for `SanctionedEntity`, and it is not decorative:
  # `harmonize_command.rb#transform_tr` builds `Tr::Entity.from_hash(data)`.
  # A split that dropped the alias would break TR harmonization while every
  # class still loaded, so it gets its own example.
  it 'keeps the Entity alias the harmonize path uses, loaded alone' do
    call = 'raise "alias missing" unless Ammitto::Sources::Tr::Entity == ' \
           'Ammitto::Sources::Tr::SanctionedEntity'
    ok, err = load_in_subprocess('ammitto/sources/tr/sanctioned_entity', call)
    expect(ok).to be(true), "alias missing when loaded alone:\n#{err}"
  end

  # `SanctionedEntity` reaches `Utils::IriSanitizer` inside
  # `.minted_segment`, a run-time edge to a file OUTSIDE this directory. The
  # load-alone sweep does not see it, and neither did an earlier version of
  # this spec: dropping that require left every example green.
  it 'sanctioned_entity reaches IriSanitizer, loaded alone' do
    call = 'raise "no segment minted" unless ' \
           'Ammitto::Sources::Tr::SanctionedEntity.minted_segment("AB-123") ' \
           '.is_a?(String)'
    ok, err = load_in_subprocess('ammitto/sources/tr/sanctioned_entity', call)
    expect(ok).to be(true), "sanctioned_entity loaded but failed on use:\n#{err}"
  end

  # `roo` is a gem, not a sibling, and `SanctionsList.from_xlsx` is the only
  # thing that names it. Reaching it needs a real workbook, which this spec
  # does not build; `spec/ammitto/sources/tr/sanctions_list_spec.rb` covers
  # that path with a fixture. Recorded rather than left implied: dropping
  # `require 'roo'` does NOT fail this file.

  # The three run-time edges. A stub sheet is enough for two of them: both
  # methods ask it only for `row`. Two headers that normalise onto one
  # consumed field is the condition `.header_fields` raises on, so this
  # reaches the constant rather than merely calling the method.
  it 'sanctions_list raises IntegrityError on collapsing headers, loaded alone' do
    call = <<~RUBY.gsub(/\s+/, ' ')
      sheet = Object.new;
      def sheet.row(_n) = ["Sıra No", "Sira No"];
      begin;
        Ammitto::Sources::Tr::SanctionsList.header_fields(sheet);
        raise "expected IntegrityError, got none";
      rescue Ammitto::Sources::Tr::IntegrityError;
        :ok;
      end
    RUBY
    ok, err = load_in_subprocess('ammitto/sources/tr/sanctions_list', call)
    expect(ok).to be(true), "sanctions_list loaded but failed on use:\n#{err}"
  end

  # The edge the split dropped. `verify_reservations!` runs on every harvest,
  # so a missing require here fails the fetch rather than a corner of it.
  #
  # One entity, not none: the sanitizer is named inside the `holders` select,
  # which an empty list never enters. This entity holds and claims nothing
  # reserved, so the method returns normally, and returning IS the proof --
  # a missing require would have raised NameError before reaching the end.
  it 'sanctions_list reaches IriSanitizer from verify_reservations!, loaded alone' do
    call = <<~RUBY.gsub(/\s+/, ' ')
      entity = Ammitto::Sources::Tr::SanctionedEntity.new(name: "Not A Holder",
                                                          reference_number: "1");
      Ammitto::Sources::Tr::SanctionsList.verify_reservations!([entity])
    RUBY
    ok, err = load_in_subprocess('ammitto/sources/tr/sanctions_list', call)
    expect(ok).to be(true), "sanctions_list loaded but failed on use:\n#{err}"
  end

  # ...and the assertion no behavioural example CAN make.
  #
  # Removing `sanctions_list.rb`'s own sanitizer require leaves every example
  # above green, because `sanctioned_entity.rb` requires the same file and
  # `sanctions_list.rb` requires that. Measured: dropping it from one file
  # fails nothing; dropping it from both fails two examples. A behavioural
  # test cannot tell a declared dependency from a borrowed one; only reading
  # the file can.
  #
  # `Date` is here for the same reason and is the other borrowed one:
  # `.cell_text` names it in a `when Date`, and it arrives only because
  # lutaml/model happens to load it. That one predates the split.
  #
  # Whole lines, not a substring: `include?` on the source is satisfied by
  # the same text inside a comment, which declares nothing.
  it 'sanctions_list declares the requires it cannot borrow' do
    source = File.read(File.expand_path(
                         '../../../../lib/ammitto/sources/tr/sanctions_list.rb',
                         __dir__
                       ))
    expect(source.lines.map(&:chomp))
      .to include("require 'date'",
                  "require_relative '../../utils/iri_sanitizer'")
  end

  it 'sanctions_list reaches SanctionedEntity from read_row, loaded alone' do
    call = <<~RUBY.gsub(/\s+/, ' ')
      sheet = Object.new;
      def sheet.row(_n) = ["12345"];
      out = Ammitto::Sources::Tr::SanctionsList.read_row(sheet, 2, [:reference_number]);
      raise "did not reach SanctionedEntity" unless out[:reference_number] == "12345"
    RUBY
    ok, err = load_in_subprocess('ammitto/sources/tr/sanctions_list', call)
    expect(ok).to be(true), "sanctions_list loaded but failed on use:\n#{err}"
  end
end
