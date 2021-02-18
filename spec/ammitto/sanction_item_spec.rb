# frozen_string_literal: true

RSpec.describe "Ammitto" => :SanctionItem do
  context "instance" do
    subject do
      hash = YAML.load_file "spec/examples/sanction_item.yml"
      Ammitto::SanctionItem.new(hash)
    end

    it "is instance of SanctionItem" do
      expect(subject).to be_instance_of Ammitto::SanctionItem
    end

    it "has array of names" do
      expect(subject.names).to be_instance_of(Array)
      expect(subject.names.first).to eq("HAMID HAMAD HAMID AL-‘ALI")
    end

    it "has array of valid addresses" do
      expect(subject.addresses).to be_instance_of(Array)
      expect(subject.addresses.first).to be_instance_of Ammitto::Address
      expect(subject.addresses.first.to_hash).to be_instance_of(Hash)
    end

    it 'should respond to_hash with expected hash' do
      expected_hash = {"names"=>["HAMID HAMAD HAMID AL-‘ALI", "HAMID HAMAD AL-‘ALI", "HAMID HAMAD ALI"], "source"=>"un_sanctions_list", "entity_type"=>"person",
                       "country"=>"Kuwait", "birthdate"=>"1960-11-17", "ref_number"=>"QDi.326", "ref_type"=>"Al-Qaida",
                       "remark"=>"A Kuwait-based financier, recruiter and facilitator for Islamic State in\nIraq and the Levant, listed as Al-Qaida in Iraq (QDe.115), and Jabhat al-Nusrah, listed\nas Al-Nusrah Front for the People of the Levant (QDe.137).",
                       "addresses"=>[{"street"=>"Barangay Mangayao", "city"=>"Tagkawayan", "state"=>"Quezon", "country"=>"Philippines", "zip"=>"30141"}, {"street"=>"Barangay Tigib", "city"=>"Ayungon", "state"=>"Negros Oriental", "country"=>"Philippines", "zip"=>"30141"}],
                       "documents" => [{"passport"=>{"country"=>"Kuwait", "note"=>"Dual Passport", "number"=>"001714467", "type"=>"Passport"}}, {"passport"=>{"country"=>"Kuwait", "note"=>"Second Passport", "number"=>"101505554", "type"=>"Passport"}}]}
      expect(subject.to_hash).to eq(expected_hash)
    end

    it 'should respond to_xml with expected xml' do
        xml = subject.to_xml
        expect(xml).to be_equivalent_to <<~XML
               <sanction_item>
         <names>
           <name>HAMID HAMAD HAMID AL-‘ALI</name>
           <name>HAMID HAMAD AL-‘ALI</name>
           <name>HAMID HAMAD ALI</name>
         </names>
         <source>un_sanctions_list</source>
         <entity_type>person</entity_type>
         <country>Kuwait</country>
         <country>Kuwait</country>
         <birthdate>1960-11-17</birthdate>
         <ref_number>QDi.326</ref_number>
         <ref_type>Al-Qaida</ref_type>
         <remark>A Kuwait-based financier, recruiter and facilitator for Islamic State in
       Iraq and the Levant, listed as Al-Qaida in Iraq (QDe.115), and Jabhat al-Nusrah, listed
       as Al-Nusrah Front for the People of the Levant (QDe.137).</remark>
         <addresses>
           <address>
             <street>Barangay Mangayao</street>
             <city>Tagkawayan</city>
             <state>Quezon</state>
             <country>Philippines</country>
             <zip>30141</zip>
           </address>
           <address>
             <street>Barangay Tigib</street>
             <city>Ayungon</city>
             <state>Negros Oriental</state>
             <country>Philippines</country>
             <zip>30141</zip>
           </address>
         </addresses>
         <documents>
           <passport>
             <type>Passport</type>
             <number>001714467</number>
             <country>Kuwait</country>
             <note>Dual Passport</note>
           </passport>
           <passport>
             <type>Passport</type>
             <number>101505554</number>
             <country>Kuwait</country>
             <note>Second Passport</note>
           </passport>
         </documents>
       </sanction_item>
        XML
    end


    it "has array of documents with proper type" do
      expect(subject.addresses).to be_instance_of(Array)
      expect(subject.documents.first).to be_instance_of Ammitto::Passport
    end

  end
end
