= Fix NAME_SCRIPTS enum corruption (M2)
Defect: inline comments inside %i[] -> 37 members incl :"#"; Greek should be Grek (ISO 15924); jp emits Jpan which enum lacks.
Where: ontology/types.rb:109-122; sources/jp/transformer.rb:90. Accept: valid_script?('#') false; Grek/Jpan valid. Size S.
