# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli/fetch/item_mapper'

# `fetch` named a record's file after an identifier the source did not give it.
#
# Every branch of the old `filename_for_item` read `a || b || "unknown-#{id}"`,
# and `||` only catches nil. An empty string is truthy in Ruby, so a Canadian
# record whose id was "" produced `ca-.yaml`: seven bytes of `--- {}` written
# as though it were a sanctions record. Harmonize's health gate refused it, and
# that refusal blocked `ammitto/data` and the site build from 2026-08-25 until
# it was traced two days later.
#
# The `"unknown-#{item.object_id}"` tail was the second half of the same fault.
# It fabricates an identifier, and `object_id` is not stable between runs, so
# the same record would land in a different file each harvest. No such file
# exists in any data repository, so it never fired — a trap rather than a
# behaviour.
#
# `identifier_for_item` used to hold a 16-branch `case` picking WHICH fields a
# source's item carries, each candidate then filtered for presence here. That
# knowledge now lives on the item classes themselves, one `#identifier` method
# per class (see spec/ammitto/sources/**/*_identifier_spec.rb for the
# per-source candidate-priority and blank-string regression coverage this file
# used to hold). What is left here is ItemMapper's own remaining job: asking
# an item for its identifier and turning a present one into a filename with
# the right per-source prefix — so these specs use doubles that answer
# `#identifier` directly, the same way `#items_from_data`'s doubles answer
# `#items` directly, rather than re-deriving it from raw per-source fields.
RSpec.describe Ammitto::Cmd::Fetch::ItemMapper do
  # ItemMapper depends on nothing FetchCommand supplies, so it is exercised
  # directly here rather than through a FetchCommand instance.
  subject(:command) { Class.new { include Ammitto::Cmd::Fetch::ItemMapper }.new }

  # A stand-in that answers the attribute readers a branch asks for and
  # nothing else. Not OpenStruct: RuboCop's Style/OpenStructUse rejects it,
  # and a record that answers ANY method would hide a branch reading the
  # wrong one.
  def record(attrs)
    Class.new do
      def initialize(attrs) = @attrs = attrs

      def respond_to_missing?(name, _ = false) = @attrs.key?(name)

      def method_missing(name, *)
        return @attrs[name] if @attrs.key?(name)

        super
      end
    end.new(attrs)
  end

  # `items_from_data` used to be a 15-branch case picking a different
  # attribute per source; every fetchable source class now defines its own
  # `#items` instead (see spec/ammitto/sources/*/…_spec.rb for the
  # per-source nil-safety regression coverage), and this method's whole
  # job is delegating to it.
  describe '#items_from_data' do
    it "returns the parsed data's own #items" do
      data = record(items: %w[one two])

      expect(command.send(:items_from_data, :uk, data)).to eq(%w[one two])
    end

    it 'refuses data that carries no #items, naming the source' do
      data = record(source: 'wat') # responds to something, just not #items

      expect { command.send(:items_from_data, :cn, data) }
        .to raise_error(Ammitto::ParseError, /cn: parsed data has no #items/)
    end
  end

  describe '#identifier_for_item' do
    it "delegates to the item's own #identifier" do
      item = record(identifier: 'AU9')

      expect(command.send(:identifier_for_item, :au, item)).to eq('AU9')
    end

    it 'passes through nil rather than substituting anything' do
      item = record(identifier: nil)

      expect(command.send(:identifier_for_item, :au, item)).to be_nil
    end
  end

  describe 'a record with no usable identifier' do
    it 'refuses rather than naming a file after an id it does not have' do
      item = record(identifier: nil)

      expect { command.send(:filename_for_item, :ca, item) }
        .to raise_error(Ammitto::ParseError, /no usable identifier/)
    end

    it 'names the source, so an operator knows which harvest to look at' do
      item = record(identifier: nil)

      expect { command.send(:filename_for_item, :ca, item) }
        .to raise_error(/^ca: /)
    end
  end

  # The corpus is named by these rules. A change here renames every published
  # record in all fifteen data repositories on the next harvest, so this holds
  # the exact output of the `||`-chain version that came before. Each
  # `identifier` value here is already the resolved value a real item class's
  # `#identifier` would return — the per-source priority and blank-string
  # fallback that produces it is covered where that logic now lives, on the
  # item classes themselves.
  describe 'the filenames every published record already has' do
    {
      uk: ['GBR-0123', 'gbr-0123.yaml'],
      eu: ['EU.1234.99', 'eu-1234-99.yaml'],
      un: ['QDi.001', 'qdi-001.yaml'],
      us: ['12345', '12345.yaml'],
      wb: [777, 'wb-777.yaml'],
      au: ['AU9', 'au-AU9.yaml'],
      ca: ['Iran-1-Part-1-17', 'ca-Iran-1-Part-1-17.yaml'],
      ch: ['SSID-42', 'ch-SSID-42.yaml'],
      cn: ['Acme Corp', 'cn-acme-corp.yaml'],
      ru: ['Ivan Ivanov', 'ru-ivan-ivanov.yaml'],
      tr: ['TR-7', 'tr-tr-7.yaml'],
      nz: ['NZ 12', 'nz-nz-12.yaml'],
      jp: ['JP1', 'jp-JP1.yaml'],
      eu_vessels: ['9999999', 'eu-vessel-9999999.yaml'],
      un_vessels: ['some-ship', 'un-vessel-some-ship.yaml']
    }.each do |source, (identifier, expected)|
      it "keeps #{source}'s filename unchanged" do
        expect(command.send(:filename_for_item, source, record(identifier: identifier)))
          .to eq(expected)
      end
    end
  end
end
