# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Loading a file alone is not enough to prove it stands alone.
#
# gem #90 fixed the top-level models for constants named when a file is
# READ — `attribute :x, SomeClass`, `class X < Y`. Those raise on require,
# so a sweep that loads each file in its own process finds them.
#
# A constant named inside a method body is different: Ruby does not resolve
# it until the method runs. The file loads clean and raises NameError on
# first use, and a load-only sweep is green the whole time. That was true
# of both files here.
#
# So every example below must ENTER the method that names the constant.
# Building the receiver is not enough, and neither is calling a method that
# returns before reaching the name — `create_reason` skips LocalizedString
# entirely when `description` is nil, which is why each call below carries
# the arguments that get it as far as the constant.
RSpec.describe 'files that name a constant inside a method body' do
  # In-process would prove nothing: RSpec has required the whole tree by
  # the time an example runs. Keeping stderr matters — the failure is a
  # NameError naming the constant, and discarding it leaves the message as
  # a bare "expected true, got false".
  def call_in_subprocess(path, call)
    lib = File.expand_path('../../../lib', __dir__)
    err = Tempfile.new('isolated_call')
    ok = system(RbConfig.ruby, '-I', lib, '-e', "require '#{path}'; #{call}",
                out: File::NULL, err: err.path)
    [ok, File.read(err.path)]
  ensure
    err&.close
    err&.unlink
  end

  describe 'ammitto/transformers/base_transformer' do
    PATH = 'ammitto/transformers/base_transformer'

    SUBCLASS = 'k = Class.new(Ammitto::Transformers::BaseTransformer) ' \
               '{ def default_list_type = :x }; t = k.new(:cn); '

    # One call per require the file carries, each reaching a different
    # constant. Fewer would leave a require nothing protects.
    {
      'Authority' => 't.send(:authority)',
      'NameVariant' => 't.send(:create_name_variant, full_name: "x")',
      'Address' => 't.send(:create_address, city: "x")',
      'BirthInfo' => 't.send(:create_birth_info, year: 1970)',
      'Identification' => 't.send(:create_identification, number: "x")',
      'RawSourceData' => 't.send(:create_raw_source_data, source_file: "x")',
      'SanctionEffect' => 't.send(:create_effect, effect_type: "x")',
      'SanctionRegime' => 't.send(:create_regime, code: "x")',
      'TemporalPeriod' => 't.send(:create_period, listed_date: "2026-01-01")',
      'Ontology::ValueObjects::LocalizedString and SanctionReason' =>
        't.send(:create_reason, category: "x", description: "y")'
    }.each do |const, call|
      it "resolves #{const}, loaded alone" do
        ok, err = call_in_subprocess(PATH, SUBCLASS + call)
        expect(ok).to be(true), "loaded but failed on use:\n#{err}"
      end
    end
  end

  describe 'ammitto/data/knowledge_graph_loader' do
    # `harmonize_names` calls Ontology::Types.detect_script on the
    # `full_name` branch. `allocate` skips the initializer, which wants a
    # directory that does not exist here and has nothing to do with the
    # constant under test.
    it 'resolves Ontology::Types, loaded alone' do
      ok, err = call_in_subprocess(
        'ammitto/data/knowledge_graph_loader',
        'Ammitto::Data::KnowledgeGraphLoader.allocate' \
        '.send(:harmonize_names, [{ "full_name" => "Zhang" }])'
      )
      expect(ok).to be(true), "loaded but failed on use:\n#{err}"
    end
  end
end
