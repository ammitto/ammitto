# Ammitto

Retrieve sanctioned people and organizations from various reputed published sources
## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ammitto'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ammitto

## Usage

```ruby
require 'ammitto'
Ammitto::search(SEARCH_TERM,options) # options is a hash is not mandatory
# e.g. Ammitto::search('Salih')
```
will search for a part of a name or full name of an entity according to the `SEARCH_TERM` and respond with a `Ammitto::SanctionItemCollection` object, which contains a collection of `Ammitto::SanctionItem`

#### Options

advanced search `options` can be passed to the search function. Here is the list of options accepted:
 
* entity_type  - value can be 'person' or 'organization'
* source 
* ref_number
* ref_type
* country
* remark
* designation

* document[:type]
* document[:number]
* document[:country]
* document[:note]
   
* address[:street]
* address[:city]
* address[:country]
* address[:state]
* address[:zip]
 
 All option values has to be of `String` type. The search options can be passed one or more at once and will be treated as `AND`.
 Here is an example search with options passed:
 ```ruby
 Ammitto::search("CORONADO",{ref_number:'343106',addresses: {street: 'HOSPITAL HUMBERTO ALVARADO'}})
```   
Search will match exact or a part of the string to extract result.

#### Example response: 
```
#<Ammitto::SanctionItem:0x00005586c8205158 
    @names=["HAMID HAMAD HAMID AL-‘ALI", "HAMID HAMAD AL-‘ALI", "HAMID HAMAD ALI"], 
    @source="un_sanctions_list", 
    @entity_type="person", 
    @country="Kuwait", 
    @birthdate="1960-11-17", 
    @ref_number="QDi.326", 
    @ref_type="Al-Qaida", 
    @remark="A Kuwait-based financier, recruiter and facilitator for Islamic State in\nIraq and the Levant, listed as 
    Al-Qaida in Iraq (QDe.115), and Jabhat al-Nusrah, listed\nas Al-Nusrah Front for the People of the Levant (QDe.137).", 
    @addresses=[
        #<Ammitto::Address:0x00005586c8205090 
            @street="Barangay Mangayao", 
            @city="Tagkawayan", 
            @state="Quezon", 
            @country="Philippines", 
            @zip="30141">, 
        #<Ammitto::Address:0x00005586c8205068 
            @street="Barangay Tigib", 
            @city="Ayungon", 
            @state="Negros Oriental", 
            @country="Philippines", 
            @zip="30141">], 
    @documents=[
        #<Ammitto::Document:0x00005586c8204f50 
            @type="Passport", 
            @number="001714467", 
            @country="Kuwait", 
            @note="Dual Passport">, 
        #<Ammitto::Document:0x00005586c8204f28 
            @type="Passport", 
            @number="101505554", 
            @country="Kuwait", 
            @note="Second Passport">]>
```

## Response Object Details

`Ammitto::SanctionItem` has the following fields:
  
 * names(`Array`) - Array of name and alias of an entity
 * source(`String`) - Source of this entity
 * entity_type(`String`) - Is the entity is a person or organization
 * country(`String`) - country of the entity
 * birthdate(`String`) - birth date of the entity
 * ref_number(`String`) - reference number of the entity in the source document 
 * ref_type(`String`) - reference type of the entity in the source document 
 * remark(`String`) - remark/comment for the entity
 * contact(`String`) - contact of the entity
 * designation(`String`) - designation of the entity
 * addresses(`Array`) - Array of `Ammitto::Address` objects
 * documents(`Array`) - Array of `Ammitto::Document` objects
 
 `Ammitto::Address` has the following fields:
 * street(`String`) 
 * city(`String`) 
 * state(`String`)
 * country(`String`)
 * zip(`String`) - zip or post code
 
 `Ammitto::Document` has the following fields:
 * type(`String`) - type of the document
 * number(`String`) - document number e.g. passpost or NID number
 * country(`String`)
 * note(`String`)
 
`Ammitto::SanctionItem` has standard `to_hash` and `to_xml` methods.

### Update Data Source
Data sources will be updated automatically once in 24 hours. To update data sources on demand
```ruby
Ammitto::update_data_source
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ammitto/ammitto. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ammitto/ammitto/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ammitto project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/ammitto/ammitto/blob/master/CODE_OF_CONDUCT.md).
