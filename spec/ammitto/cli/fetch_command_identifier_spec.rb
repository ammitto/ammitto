# frozen_string_literal: true

require 'thor'
require 'ammitto'
require 'ammitto/cli/fetch_command'

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
RSpec.describe Ammitto::Cmd::FetchCommand do
  subject(:command) { described_class.new({}, ['ca']) }

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

  describe 'a record with no usable identifier' do
    it 'refuses rather than naming a file after an id it does not have' do
      item = record(generate_id: '', item: nil)

      expect { command.send(:filename_for_item, :ca, item) }
        .to raise_error(Ammitto::ParseError, /no usable identifier/)
    end

    it 'treats whitespace as absent, not as an identifier' do
      item = record(generate_id: '   ', item: nil)

      expect { command.send(:filename_for_item, :ca, item) }
        .to raise_error(Ammitto::ParseError)
    end

    # ch reached `full_name&.gsub(/\s+/, '-')`, which turns "" into "" rather
    # than nil, so the safe-navigation operator did not help.
    it 'closes the same hole where a gsub kept a blank string blank' do
      item = record(ssid: nil, full_name: '')

      expect { command.send(:filename_for_item, :ch, item) }
        .to raise_error(Ammitto::ParseError)
    end

    it 'names the source, so an operator knows which harvest to look at' do
      item = record(generate_id: nil, item: nil)

      expect { command.send(:filename_for_item, :ca, item) }
        .to raise_error(/^ca: /)
    end
  end

  describe 'a blank first candidate' do
    it 'falls through to the next one instead of winning' do
      item = record(generate_id: '', item: 'Iran-9')

      expect(command.send(:filename_for_item, :ca, item)).to eq('ca-Iran-9.yaml')
    end
  end

  # The corpus is named by these rules. A change here renames every published
  # record in all fifteen data repositories on the next harvest, so this holds
  # the exact output of the `||`-chain version that came before.
  describe 'the filenames every published record already has' do
    {
      uk: [{ unique_id: 'GBR-0123' }, 'gbr-0123.yaml'],
      eu: [{ eu_reference_number: 'EU.1234.99' }, 'eu-1234-99.yaml'],
      un: [{ reference_number: 'QDi.001' }, 'qdi-001.yaml'],
      us: [{ uid: '12345' }, '12345.yaml'],
      wb: [{ supp_id: '777' }, 'wb-777.yaml'],
      au: [{ reference: 'AU9', id: nil }, 'au-AU9.yaml'],
      ca: [{ generate_id: 'Iran-1-Part-1-17', item: nil }, 'ca-Iran-1-Part-1-17.yaml'],
      ch: [{ ssid: 'SSID-42', full_name: nil }, 'ch-SSID-42.yaml'],
      cn: [{ english_name: 'Acme Corp', chinese_name: nil }, 'cn-acme-corp.yaml'],
      ru: [{ english_name: 'Ivan Ivanov', russian_name: nil }, 'ru-ivan-ivanov.yaml'],
      tr: [{ local_id: 'TR-7', name: nil }, 'tr-tr-7.yaml'],
      nz: [{ unique_identifier: 'NZ 12', reference_number: nil }, 'nz-nz-12.yaml'],
      jp: [{ id: 'JP1', unique_identifier: nil }, 'jp-JP1.yaml'],
      eu_vessels: [{ imo_number: '9999999', unique_identifier: nil },
                   'eu-vessel-9999999.yaml'],
      un_vessels: [{ local_id: 'some-ship' }, 'un-vessel-some-ship.yaml']
    }.each do |source, (attrs, expected)|
      it "keeps #{source}'s filename unchanged" do
        expect(command.send(:filename_for_item, source, record(attrs)))
          .to eq(expected)
      end
    end
  end
end
