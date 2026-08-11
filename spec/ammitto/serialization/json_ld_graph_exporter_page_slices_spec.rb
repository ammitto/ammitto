# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# The organization and document-type pages used to answer their question by
# fetching every entry node in the corpus and testing each one. These slices
# move that aggregation into the publishing pipeline, so the specs below pin
# the exact semantics the pages implemented — including the ones that look
# like defects, because changing them here would change what a visitor sees.
RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  subject(:exporter) do
    described_class.new(output_dir: output_dir, context_url: context_url)
  end

  let(:output_dir) { Dir.mktmpdir('ammitto_page_slices') }
  let(:context_url) { 'https://www.ammitto.org/ontology/context.jsonld' }

  after { FileUtils.rm_rf(output_dir) }

  def organization(identifier)
    {
      '@id' => "https://www.ammitto.org/organization/#{identifier}",
      '@type' => 'Organization',
      'identifier' => identifier
    }
  end

  def document_type(identifier)
    {
      '@id' => "https://www.ammitto.org/document-type/#{identifier}",
      '@type' => 'DocumentType',
      'identifier' => identifier
    }
  end

  def add_entry(local_id, announcement, group_id: nil, source: :cn)
    entry = {
      '@id' => "https://www.ammitto.org/entry/cn/list/#{local_id}",
      '@type' => 'SanctionEntry',
      'announcement' => announcement
    }
    entry['groupId'] = group_id if group_id
    entity = { '@id' => "https://www.ammitto.org/entity/cn/#{local_id}" }
    exporter.add_node(entity: entity, entry: entry, source: source)
  end

  def announcement(**overrides)
    {
      'title' => 'Title',
      'documentId' => 'DOC-1',
      'publishDate' => '2024-01-01',
      'url' => 'https://example.test/doc-1',
      'publisher' => 'cn/mofcom',
      'signatory' => 'cn/mofcom',
      'authority' => 'cn/mofcom',
      'documentType' => 'cn/order'
    }.merge(overrides.transform_keys(&:to_s))
  end

  def slice(*path)
    JSON.parse(File.read(File.join(output_dir, *path)))
  end

  describe 'by-organization slices' do
    it 'keeps the three roles separate rather than bleeding one into another' do
      exporter.add_organization(organization('cn/publisher-org'))
      exporter.add_organization(organization('cn/signatory-org'))
      exporter.add_organization(organization('cn/authority-org'))
      add_entry('a1', announcement(publisher: 'cn/publisher-org',
                                   signatory: 'cn/signatory-org',
                                   authority: 'cn/authority-org'))
      exporter.export

      publisher = slice('by-organization', 'cn', 'publisher-org.jsonld')
      signatory = slice('by-organization', 'cn', 'signatory-org.jsonld')
      authority = slice('by-organization', 'cn', 'authority-org.jsonld')

      expect(publisher.values_at('published', 'signed', 'authorized'))
        .to match([[a_hash_including('documentId' => 'DOC-1')], [], []])
      expect(signatory.values_at('published', 'signed', 'authorized'))
        .to match([[], [a_hash_including('documentId' => 'DOC-1')], []])
      expect(authority.values_at('published', 'signed', 'authorized'))
        .to match([[], [], [a_hash_including('documentId' => 'DOC-1')]])
    end

    it 'deduplicates entries of one document into a single counted summary' do
      exporter.add_organization(organization('cn/mofcom'))
      # Added in reverse of index order, so an implementation that followed
      # insertion order instead of the sorted entry index would let 'b1'
      # win the shared fields and fail here.
      add_entry('b1', announcement(documentId: 'DOC-1', title: 'Later title',
                                   publishDate: '2025-12-31',
                                   url: 'https://example.test/later'))
      add_entry('a1', announcement(documentId: 'DOC-1'), group_id: 'https://www.ammitto.org/group/cn/1')
      add_entry('a3', announcement(documentId: 'DOC-2', publishDate: '2023-01-01'))
      exporter.export

      published = slice('by-organization', 'cn', 'mofcom.jsonld')['published']

      expect(published.map { |s| s.values_at('documentId', 'entryCount') })
        .to eq([['DOC-1', 2], ['DOC-2', 1]])
      # The first entry in index order supplies the rendered fields; a later
      # entry of the same document must not overwrite them.
      expect(published.first).to include(
        'title' => 'Title',
        'publishDate' => '2024-01-01',
        'url' => 'https://example.test/doc-1',
        'groupId' => 'https://www.ammitto.org/group/cn/1'
      )
    end

    it 'emits summaries in entry-index order, leaving the sort to the page' do
      exporter.add_organization(organization('cn/mofcom'))
      # Inserted newest-first and lexically-last-first, so neither insertion
      # order nor a producer-side date sort would produce this sequence:
      # only the sorted entry index does.
      add_entry('z1', announcement(documentId: 'NEW', publishDate: '2030-01-01'))
      add_entry('a1', announcement(documentId: 'OLD', publishDate: '2001-01-01'))
      exporter.export

      published = slice('by-organization', 'cn', 'mofcom.jsonld')['published']

      expect(published.map { |s| s['documentId'] }).to eq(%w[OLD NEW])
    end

    it 'omits an absent title, url and group rather than emitting null' do
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement.tap { |a| a.delete('title') and a.delete('url') })
      exporter.export

      summary = slice('by-organization', 'cn', 'mofcom.jsonld')['published'].first

      expect(summary.keys).to contain_exactly('documentId', 'publishDate', 'entryCount')
    end

    it 'names the organization it summarizes' do
      exporter.add_organization(organization('cn/mofcom'))
      exporter.export

      expect(slice('by-organization', 'cn', 'mofcom.jsonld')).to include(
        '@type' => 'Index',
        'slice' => 'by-organization',
        'organization' => { '@id' => 'https://www.ammitto.org/organization/cn/mofcom' }
      )
    end

    it 'reflects entries added between two exports' do
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement(documentId: 'FIRST'))
      exporter.export
      add_entry('a2', announcement(documentId: 'SECOND'))
      exporter.export

      published = slice('by-organization', 'cn', 'mofcom.jsonld')['published']

      expect(published.map { |s| s['documentId'] }).to eq(%w[FIRST SECOND])
    end

    it 'groups a blank document id under "unknown", as the page does' do
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement(documentId: ''))
      add_entry('a2', announcement.tap { |a| a.delete('documentId') })
      exporter.export

      published = slice('by-organization', 'cn', 'mofcom.jsonld')['published']

      expect(published.map { |s| s.values_at('documentId', 'entryCount') })
        .to eq([['unknown', 2]])
    end

    it 'reports a missing publish date as the empty string the page sorts on' do
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement.tap { |a| a.delete('publishDate') })
      exporter.export

      expect(slice('by-organization', 'cn', 'mofcom.jsonld')['published'].first)
        .to include('publishDate' => '')
    end

    it 'preserves the raw title so each page keeps its own resolver' do
      localized = [{ 'zh-Hans' => '标题' }, { 'en' => 'Title' }]
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement(title: localized))
      exporter.export

      expect(slice('by-organization', 'cn', 'mofcom.jsonld')['published'].first['title'])
        .to eq(localized)
    end

    it 'reproduces the page substring match, including its over-inclusion' do
      # PRE-EXISTING DEFECT, reproduced deliberately: the page tests
      # `publisher === id || publisher.includes(id)`, so a parent
      # organization absorbs every child whose identifier extends it.
      exporter.add_organization(organization('cn/mofcom'))
      exporter.add_organization(organization('cn/mofcom-bureau'))
      add_entry('a1', announcement(publisher: 'cn/mofcom', documentId: 'PARENT'))
      add_entry('a2', announcement(publisher: 'cn/mofcom-bureau', documentId: 'CHILD'))
      exporter.export

      parent = slice('by-organization', 'cn', 'mofcom.jsonld')['published']
      child = slice('by-organization', 'cn', 'mofcom-bureau.jsonld')['published']

      expect(parent.map { |s| s['documentId'] }).to eq(%w[PARENT CHILD])
      expect(child.map { |s| s['documentId'] }).to eq(%w[CHILD])
    end

    # A deliberate narrowing, NOT page equivalence: JavaScript's
    # `.includes` would treat an array as a member test and would throw on
    # a number, aborting the page's whole scan. OfficialAnnouncement
    # declares these fields as strings, so the producer matches strings and
    # skips everything else instead of inventing a match.
    it 'skips a non-string relationship value instead of coercing it' do
      exporter.add_organization(organization('cn/mofcom'))
      add_entry('a1', announcement(publisher: ['cn/mofcom']))
      add_entry('a2', announcement(publisher: 42))
      exporter.export

      expect(slice('by-organization', 'cn', 'mofcom.jsonld')['published']).to eq([])
    end

    it 'writes a master index listing every organization slice' do
      exporter.add_organization(organization('cn/zeta'))
      exporter.add_organization(organization('cn/alpha'))
      exporter.export

      expect(slice('by-organization', 'index.jsonld')).to include(
        'slice' => 'by-organization',
        'available' => %w[
          https://www.ammitto.org/organization/cn/alpha
          https://www.ammitto.org/organization/cn/zeta
        ]
      )
    end
  end

  describe 'by-document-type slices' do
    it 'matches announcements on exact document type, never on a prefix' do
      exporter.add_document_type(document_type('cn/order'))
      add_entry('a1', announcement(documentType: 'cn/order', documentId: 'EXACT'))
      add_entry('a2', announcement(documentType: 'cn/order-extended', documentId: 'PREFIXED'))
      exporter.export

      announcements = slice('by-document-type', 'cn', 'order.jsonld')['announcements']

      expect(announcements.map { |s| s['documentId'] }).to eq(%w[EXACT])
    end

    it 'includes only the legal instruments carrying that document type' do
      exporter.add_document_type(document_type('cn/order'))
      exporter.instruments['https://www.ammitto.org/legal-instrument/cn/b-law'] = {
        '@id' => 'https://www.ammitto.org/legal-instrument/cn/b-law',
        'type' => 'cn/order', 'identifier' => 'b-law',
        'title' => [{ 'en' => 'B Law' }], 'name' => 'B Law', 'publishDate' => '2020-01-01'
      }
      exporter.instruments['https://www.ammitto.org/legal-instrument/cn/a-law'] = {
        '@id' => 'https://www.ammitto.org/legal-instrument/cn/a-law',
        'type' => 'cn/order', 'identifier' => 'a-law', 'title' => 'A Law'
      }
      exporter.instruments['https://www.ammitto.org/legal-instrument/cn/other'] = {
        '@id' => 'https://www.ammitto.org/legal-instrument/cn/other',
        'type' => 'cn/act', 'identifier' => 'other', 'title' => 'Other'
      }
      exporter.export

      instruments = slice('by-document-type', 'cn', 'order.jsonld')['legalInstruments']

      # Instrument-index order, which is the sorted IRI order the page walked.
      expect(instruments.map { |i| i['identifier'] }).to eq(%w[a-law b-law])
      expect(instruments.last).to eq(
        '@id' => 'https://www.ammitto.org/legal-instrument/cn/b-law',
        'identifier' => 'b-law', 'title' => [{ 'en' => 'B Law' }],
        'name' => 'B Law', 'publishDate' => '2020-01-01'
      )
    end

    it 'writes a master index listing every document-type slice' do
      exporter.add_document_type(document_type('cn/order'))
      exporter.export

      expect(slice('by-document-type', 'index.jsonld')).to include(
        'slice' => 'by-document-type',
        'available' => %w[https://www.ammitto.org/document-type/cn/order]
      )
    end
  end

  describe 'identifier path safety' do
    it 'refuses an identifier that would escape the slice directory' do
      exporter.add_organization(organization('cn/../../escape'))

      expect { exporter.export }
        .to raise_error(Ammitto::Error, /unusable path component/)
    end

    it 'refuses an identifier that would overwrite the master index' do
      exporter.add_organization(organization('index'))

      expect { exporter.export }
        .to raise_error(Ammitto::Error, /master index/)
    end

    # Driven through slice_path rather than #export, because
    # export_document_type_nodes writes {local_id}.jsonld with no length
    # guard of its own and dies with Errno::ENAMETOOLONG first — a
    # pre-existing hazard in the node export path, reported separately.
    it 'refuses an identifier whose filename exceeds the byte budget' do
      expect { exporter.send(:slice_path, output_dir, "cn/#{'x' * 300}", 'Document type') }
        .to raise_error(Ammitto::Error, /too long/)
    end

    it 'refuses an identifier whose directory component exceeds the budget' do
      expect { exporter.send(:slice_path, output_dir, "#{'x' * 300}/order", 'Document type') }
        .to raise_error(Ammitto::Error, /too long/)
    end

    # 'cn' writes cn.jsonld and 'cn/order' writes cn/order.jsonld: the
    # '.jsonld' suffix keeps the file and the directory distinct names, so
    # one identifier being a prefix of another is not a collision.
    it 'lets an identifier coexist with one that extends it' do
      exporter.add_organization(organization('cn'))
      exporter.add_organization(organization('cn/order'))

      expect { exporter.export }.not_to raise_error
      expect(File).to exist(File.join(output_dir, 'by-organization', 'cn.jsonld'))
      expect(File).to exist(File.join(output_dir, 'by-organization', 'cn', 'order.jsonld'))
    end

    it 'refuses an identifier carrying a URL-significant character' do
      exporter.add_organization(organization('cn/a?b'))

      expect { exporter.export }
        .to raise_error(Ammitto::Error, /unusable path component/)
    end
  end
end
