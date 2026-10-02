# frozen_string_literal: true

require 'date'
require 'tmpdir'
require 'thor'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

module EuVesselsSanctionsListSpecHelpers
  # Drives the real .from_xlsx with Roo stubbed, so each example states
  # exactly the cells Roo hands back: Integer IMO numbers, Date cells.
  def parse(rows, header_row: headers)
    workbook = instance_double(Roo::Excelx, sheets: ['Sheet'], 'default_sheet=': nil,
                                            last_row: rows.size + 1)
    allow(workbook).to receive(:row) { |n| n == 1 ? header_row : rows[n - 2] }
    allow(Roo::Spreadsheet).to receive(:open).and_return(workbook)

    described_class.from_xlsx('ignored.xlsx')
  end

  def designations(vessel)
    vessel.designations.map { |d| [d.date_of_application, d.subject_to] }
  end

  # Reads an unreadable date of application, which publishes as nil; the
  # 'a reported parse failure' shared example calls it in every mode.
  def parse_unreadable
    -> { described_class.read_date('not-a-date', field: :date_of_application) }
  end
  alias raise_unreadable parse_unreadable
end

RSpec.describe Ammitto::Sources::EuVessels::SanctionsList do
  include EuVesselsSanctionsListSpecHelpers

  # The workbook's own header, including the trailing space DMA leaves on
  # "IMO number ".
  let(:headers) { ['Vessel name', 'IMO number ', 'Date of application', 'Subject to'] }
  let(:russia) { 'Article 3s (Council Regulation 833/2014)' }
  let(:port_ban) { 'Port entry ban (Council Regulation 2017/1509)' }
  let(:deregistration) { 'De-registration (Council Regulation 2017/1509)' }

  it 'reads each row\'s Subject to' do
    vessel = parse([['Alpha', 9_000_001, Date.new(2025, 5, 20), russia]]).items.first

    expect(designations(vessel)).to eq([[Date.new(2025, 5, 20), russia]])
  end

  it 'carries every row for one IMO number on one vessel, earliest first' do
    items = parse([
                    ['HAO FAN 6', 8_628_597, Date.new(2018, 3, 30), deregistration],
                    ['HAO FAN 6', 8_628_597, Date.new(2017, 10, 3), port_ban]
                  ]).items

    expect(items.map(&:identifier)).to eq(['8628597'])
    expect(designations(items.first))
      .to eq([[Date.new(2017, 10, 3), port_ban], [Date.new(2018, 3, 30), deregistration]])
  end

  it 'keeps a row DMA repeats cell for cell once' do
    row = ['Aura 1', 9_472_634, Date.new(2025, 10, 24), russia]

    expect(designations(parse([row, row.dup]).items.first).size).to eq(1)
  end

  it 'names a vessel without an IMO number after its name, never "IMO-"' do
    vessel = parse([['MIN NING DE YOU 078', nil, Date.new(2018, 3, 30), port_ban]]).items.first

    expect(vessel.identifier).to eq('min-ning-de-you-078')
  end

  it 'skips a wholly blank row' do
    items = parse([[nil, nil, nil, nil], ['Alpha', 9_000_001, Date.new(2025, 5, 20), russia]]).items

    expect(items.map(&:identifier)).to eq(['9000001'])
  end

  describe 'rows that do not read as a designation' do
    it 'refuses a Subject to value it has no mapping for, naming it' do
      expect { parse([['Alpha', 9_000_001, Date.new(2025, 5, 20), 'Travel ban (Council Regulation 2017/1509)']]) }
        .to raise_error(Ammitto::ParseError, %r{"Travel ban \(Council Regulation 2017/1509\)"})
    end

    it 'refuses a row whose cells shifted, putting a name in the IMO column' do
      expect { parse([['Alpha', 'Beta', 9_000_001, Date.new(2025, 5, 20)]]) }
        .to raise_error(Ammitto::ParseError, /row 2 .*IMO number "Beta"/)
    end

    it 'refuses a row with a cell past the last column' do
      expect { parse([['Alpha', 9_000_001, Date.new(2025, 5, 20), russia, 'extra']]) }
        .to raise_error(Ammitto::ParseError, /outside the header's columns \(5\)/)
    end

    it 'refuses a date of application that is not a date' do
      expect { parse([['Alpha', 9_000_001, 'soon', russia]]) }
        .to raise_error(Ammitto::ParseError, /date of application "soon"/)
    end

    it 'refuses a workbook without the Subject to column' do
      expect { parse([['Alpha', 9_000_001, Date.new(2025, 5, 20)]], header_row: headers.first(3)) }
        .to raise_error(Ammitto::ParseError, /lacks subject_to/)
    end
  end

  # Two names under one IMO number are not merged, so they reach the fetch
  # writer as two different records for one file, and it refuses them.
  it 'leaves conflicting rows for the fetch collision guard to refuse' do
    items = parse([
                    ['Alpha', 9_000_001, Date.new(2025, 5, 20), russia],
                    ['Beta', 9_000_001, Date.new(2025, 5, 20), russia]
                  ]).items
    command = Ammitto::Cmd::FetchCommand.new(Thor::CoreExt::HashWithIndifferentAccess.new, ['eu_vessels'])

    Dir.mktmpdir do |dir|
      expect { command.send(:write_items, :eu_vessels, items, dir) }
        .to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError, /eu-vessel-9000001\.yaml/)
    end
  end

  # A date of application the workbook writes that does not read as a date
  # refuses the row; the report keeps a trace of what the list stated.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    it_behaves_like 'a reported parse failure',
                    source: :eu_vessels, field: :date_of_application, raised_value: 'not-a-date'

    it 'counts the unreadable date of a workbook row it refuses' do
      expect { count_parse_failures { parse([['Alpha', 9_000_001, 'soon', russia]]) } }
        .to raise_error(Ammitto::ParseError, /row 2 .*date of application "soon"/)
      expect(run.count(:eu_vessels)).to eq(1)
    end

    it 'leaves a blank cell nil without reporting it' do
      expect(count_parse_failures { described_class.read_date('  ', field: :date_of_application) }).to be_nil
      expect(run.count(:eu_vessels)).to eq(0)
      expect(io.string).to be_empty
    end

    it 'does not report a value that parsed cleanly' do
      count_parse_failures { described_class.read_date('2025-05-20', field: :date_of_application) }

      expect(run.count(:eu_vessels)).to eq(0)
    end
  end
end
