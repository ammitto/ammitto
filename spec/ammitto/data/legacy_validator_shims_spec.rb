# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Legacy #errors semantics of the country validator shims: batch calls
# leave the LAST file's errors behind (empty when that file was valid),
# matching the original implementations that iterated via #validate.
RSpec.describe 'legacy validator shim #errors compatibility' do
  let(:validator) { Ammitto::Data::China::Validator.new }

  around do |example|
    Dir.mktmpdir do |dir|
      @good = File.join(dir, 'good-announcement.yml')
      File.write(@good, <<~YAML)
        announcement:
          title: "关于对有关实体实施制裁的公告"
          url: "https://www.mfa.gov.cn/announcement/1"
          publish_date: "2025-01-15"
          authority: "外交部"
          type: "制裁公告"
          document_id: "第4号"
          signatory: "外交部"
          content: "公告内容"
        sanction_details:
          instruments:
            - law: "反外国制裁法"
          entities:
            - name:
                zh-Hans: "测试实体"
                en: "Test Entity"
              type: organization
              effective_date: "2025-01-15"
              sanction_list: "反制裁清单"
              reason:
                - zh-Hans: "原因"
              measures:
                - type:
                    - asset_freeze
                  zh-Hans: "冻结资产"
      YAML
      @bad = File.join(dir, 'bad-announcement.yml')
      File.write(@bad, { 'announcement' => { 'title' => 'incomplete' } }.to_yaml)
      example.run
    end
  end

  it 'leaves the last file errors after validate_files' do
    validator.validate_files([@good, @bad])
    expect(validator.errors).not_to be_empty
  end

  it 'leaves empty errors when the last file is valid' do
    report = validator.validate_files([@bad, @good])
    expect(report[:invalid_files]).to eq(1)
    expect(validator.errors).to be_empty
  end

  it 'resets errors between batch calls' do
    validator.validate_files([@bad])
    validator.validate_files([@good])
    expect(validator.errors).to be_empty
  end

  it 'keeps last-file semantics through validate_all' do
    # Sorted glob order: bad-announcement.yml then good-announcement.yml,
    # so the last validated file is the valid one.
    report = validator.validate_all(File.dirname(@good))
    expect(report[:invalid_files]).to eq(1)
    expect(validator.errors).to be_empty
  end

  it 'returns mutable structures through the legacy surfaces' do
    report = validator.validate_files([@good, @bad])
    expect { report[:errors].first[:errors].first[:message] = 'edited' }
      .not_to raise_error
    validator.validate(@bad)
    expect { validator.errors.first[:message] = 'edited' }
      .not_to raise_error
  end
end
