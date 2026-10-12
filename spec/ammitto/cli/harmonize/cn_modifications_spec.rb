# frozen_string_literal: true

require 'yaml'
require 'json'
require 'tmpdir'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe 'Harmonizing CN measure modifications' do
  let(:root) { Dir.mktmpdir('ammitto_cn_mods') }
  let(:output_dir) { File.join(root, 'out') }
  let(:lists) { File.join(root, 'data-cn', 'sources', 'sanction-lists') }
  let(:updates) { File.join(root, 'data-cn', 'sources', 'sanction-updates', 'unreliable-entity-list-updates') }

  before { allow($stdout).to receive(:write) }
  after { FileUtils.rm_rf(root) }

  def write_yaml(dir, name, data)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), data.to_yaml)
  end

  def write_list(list, name, document_id:, publish_date:, names:)
    write_yaml(File.join(lists, list), name, {
                 'announcement' => { 'document_id' => document_id, 'publish_date' => publish_date,
                                     'url' => "https://example.gov/#{list}/#{name}" },
                 'sanction_details' => {
                   'entities' => names.map do |n|
                     { 'name' => { 'en' => n }, 'type' => 'organization',
                       'effective_date' => publish_date, 'sanction_list' => "cn/#{list}" }
                   end
                 }
               })
  end

  def write_update(name, publish_date:, modifications:, dir: updates)
    write_yaml(dir, name, {
                 'announcement' => { 'document_id' => "notice-#{publish_date}", 'publish_date' => publish_date,
                                     'url' => "https://example.gov/notice/#{publish_date}" },
                 'measure_modifications' => { 'modifications' => modifications }
               })
  end

  def suspend(target, effective, until_date, target_date: '2025-04-04')
    { 'action' => 'suspend', 'target_announcement_id' => target, 'target_announcement_date' => target_date,
      'effective_date' => effective, 'until_date' => until_date }
  end

  def stop(target, effective, target_date: '2025-04-04')
    { 'action' => 'stop', 'target_announcement_id' => target, 'target_announcement_date' => target_date,
      'effective_date' => effective }
  end

  def harmonize(sources_dir = root, output = output_dir)
    command = Ammitto::Cmd::HarmonizeCommand.new({ sources_dir: sources_dir, output_dir: output }, ['cn'])
    captured = nil
    allow(command).to receive(:enforce_health_gates).and_wrap_original do |original, results|
      captured = results.first
      original.call(results)
    end
    begin
      command.run
    rescue Thor::Error => e
      captured[:gate_error] = e.message
    end
    captured
  end

  def entries(output = output_dir)
    graph = JSON.parse(File.read(File.join(output, 'sources', 'cn.jsonld')))['@graph']
    graph.select { |node| node['@type'] == 'SanctionEntry' }.to_h { |e| [e['@id'].split('/').last(2).join('/'), e] }
  end

  def standard_tree
    write_list('unreliable-entity-list', '202507.yml', document_id: '〔2025〕7号', publish_date: '2025-04-04',
                                                       names: ['Alpha Corp', 'Beta Corp'])
    write_list('anti-sanction-list', '20250404.yml', document_id: '〔2025〕7号', publish_date: '2025-04-04',
                                                     names: ['Gamma Corp'])
    write_update('20250514.yml', publish_date: '2025-05-14',
                                 modifications: [suspend('〔2025〕7号', '2025-05-14', '2025-08-12')])
    write_update('20250812.yml', publish_date: '2025-08-12',
                                 modifications: [suspend('〔2025〕7号', '2025-08-12', '2025-11-10')])
  end

  it 'reads sanction-updates and attaches every modification to each entry of the target announcement' do
    standard_tree
    result = harmonize

    expect(result[:errors]).to be_nil
    alpha = entries['unreliable-entity-list/20257-alpha-corp']
    expect(alpha['modifications'].map { |m| m['effectiveDate'] }).to eq(%w[2025-05-14 2025-08-12])
    expect(alpha['statusHistory'].map { |c| [c['date'], c['fromStatus'], c['toStatus'], c['suspensionEndDate']] })
      .to eq([%w[2025-05-14 active suspended 2025-08-12], %w[2025-08-12 suspended suspended 2025-11-10]])
    expect(alpha['statusHistory'].first['noticeReference']['noticeNumber']).to eq('notice-2025-05-14')
    expect(entries['unreliable-entity-list/20257-beta-corp']['statusHistory'].size).to eq(2)
  end

  it 'leaves the published status unchanged' do
    standard_tree
    harmonize

    expect(entries['unreliable-entity-list/20257-alpha-corp']['statusHistory'].last['toStatus']).to eq('suspended')
    expect(entries.values.map { |e| e['status'] }.uniq).to eq(['active'])
  end

  it 'does not apply a modification to the same document number in another list' do
    standard_tree
    harmonize

    expect(entries['unreliable-entity-list/20257-alpha-corp']['modifications'].size).to eq(2)
    gamma = entries.find { |id, _| id.start_with?('anti-sanction-list/') }.last
    expect(gamma['statusHistory']).to be_empty
    expect(gamma).not_to have_key('modifications')
  end

  it 'gives the same output whatever order the update files are read in' do
    standard_tree
    harmonize
    forward = entries
    FileUtils.mv(File.join(updates, '20250514.yml'), File.join(updates, 'z-20250514.yml'))
    FileUtils.mv(File.join(updates, '20250812.yml'), File.join(updates, 'a-20250812.yml'))
    reverse_out = File.join(root, 'out2')
    harmonize(root, reverse_out)

    expect(forward['unreliable-entity-list/20257-alpha-corp']['statusHistory'].size).to eq(2)
    expect(entries(reverse_out)).to eq(forward)
  end

  it 'fails the health gate when a modification target matches no announcement' do
    standard_tree
    write_update('20251105.yml', publish_date: '2025-11-05',
                                 modifications: [stop('〔2025〕99号', '2025-11-10')])
    result = harmonize

    expect(result[:errors]).to eq(
      ['20251105.yml: modification target unreliable-entity-list/〔2025〕99号 matches no announcement']
    )
    expect(result[:gate_error]).to match(/cn: 1 file\(s\) failed to transform/)
  end

  it 'reports a target date that disagrees with the announcement' do
    standard_tree
    write_update('20251105.yml', publish_date: '2025-11-05',
                                 modifications: [stop('〔2025〕7号', '2025-11-10', target_date: '2025-04-09')])
    result = harmonize

    expect(result[:errors].join).to include('dated 2025-04-09 but the announcement was published 2025-04-04')
  end

  it 'reports a modification that follows a stop, and conflicting actions on one day' do
    standard_tree
    write_update('20251105.yml', publish_date: '2025-11-05',
                                 modifications: [stop('〔2025〕7号', '2025-11-10'),
                                                 suspend('〔2025〕7号', '2025-11-10', '2026-01-01')])
    write_update('20260101.yml', publish_date: '2026-01-01',
                                 modifications: [suspend('〔2025〕7号', '2026-01-02', '2026-02-01')])
    result = harmonize

    expect(result[:errors].join("\n")).to include('conflicts with another action the same day')
      .and include('follows a stop of the same announcement')
  end

  it 'fails the health gate when a target matches two announcements of one list' do
    standard_tree
    write_list('unreliable-entity-list', '202507b.yml', document_id: '〔2025〕7号', publish_date: '2025-04-04',
                                                        names: ['Epsilon Corp'])
    result = harmonize

    expect(result[:errors]).to include(
      '20250514.yml: modification target unreliable-entity-list/〔2025〕7号 matches 2 announcements'
    )
  end

  it 'reads updates beside an --input-dir not named sanction-lists' do
    standard_tree
    FileUtils.mv(lists, File.join(root, 'data-cn', 'sources', 'curated'))
    command = Ammitto::Cmd::HarmonizeCommand.new(
      { input_dir: File.join(root, 'data-cn', 'sources', 'curated'), output_dir: output_dir }, ['cn']
    )
    command.run

    expect(entries['unreliable-entity-list/20257-alpha-corp']['statusHistory'].size).to eq(2)
  end

  it 'reads sources/sanction-updates when the input is a processed directory' do
    standard_tree
    FileUtils.mv(lists, File.join(root, 'data-cn', 'processed'))
    harmonize

    expect(entries['unreliable-entity-list/20257-alpha-corp']['statusHistory'].size).to eq(2)
  end

  it 'reports an updates directory that names no known list' do
    standard_tree
    FileUtils.mkdir_p(File.join(root, 'data-cn', 'sources', 'sanction-updates', 'mystery-updates'))
    result = harmonize

    expect(result[:errors]).to eq(['mystery-updates: updates directory mystery-updates names no known CN list'])
  end

  describe 'the status history it builds' do
    def entry_with_history(*mods)
      write_list('unreliable-entity-list', '202508.yml', document_id: '〔2025〕8号', publish_date: '2025-04-09',
                                                         names: ['Delta Corp'])
      write_update('u.yml', publish_date: '2025-05-14', modifications: mods)
      transformer = Ammitto::Sources::Cn::Transformer.new
      transformer.modification_index = Ammitto::Sources::Cn::ModificationIndex.build(File.dirname(updates),
                                                                                     transformer)
      data = YAML.safe_load_file(File.join(lists, 'unreliable-entity-list', '202508.yml'))
      transformer.transform_announcement(Ammitto::Sources::Cn::Announcement.from_hash(data))[:entries].first
    end

    it 'answers status_as_of across chained suspensions' do
      entry = entry_with_history(suspend('〔2025〕8号', '2025-05-14', '2025-08-12', target_date: '2025-04-09'),
                                 suspend('〔2025〕8号', '2025-08-12', '2025-11-10', target_date: '2025-04-09'))

      expect(%w[2025-05-13 2025-05-14 2025-08-12 2025-11-10 2025-11-11].map { |d| entry.status_as_of(d) })
        .to eq(%w[active suspended suspended suspended active])
      expect(entry.status).to eq('active')
    end

    it 'answers status_as_of for a suspension then a stop' do
      entry = entry_with_history(suspend('〔2025〕8号', '2025-05-14', '2025-08-12', target_date: '2025-04-09'),
                                 stop('〔2025〕8号', '2025-08-12', target_date: '2025-04-09'))

      expect(%w[2025-05-13 2025-05-14 2025-08-11 2025-08-12 2026-01-01].map { |d| entry.status_as_of(d) })
        .to eq(%w[active suspended suspended terminated terminated])
    end
  end
end
