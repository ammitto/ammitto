# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Uk
      # Maps a wrapper element holding repeated text children, for example
      # <DOBs><DOB>..</DOB></DOBs>, onto one flat string collection.
      #
      # Lutaml::Model drops a collection that sits one element below the
      # model it belongs to, so each list is read through a custom mapping.
      # Keeping the attribute flat keeps the fetched YAML flat as well.
      #
      # @example
      #   class Individual < Lutaml::Model::Serializable
      #     extend XmlTextList
      #     attribute :dobs, :string, collection: true
      #     text_list :dobs, 'DOB'
      #     xml { map_element 'DOBs', to: :dobs, **XmlTextList.handlers(:dobs) }
      #   end
      module XmlTextList
        # Defines the readers a text-list mapping calls. The xml block is
        # evaluated on the mapping, not the model, so the handlers are
        # defined here and named later through {handlers}.
        #
        # Writing XML back is not supported: the gem only reads OFSI XML.
        #
        # @param attr [Symbol] the string collection attribute
        # @param child [String] the repeated child element name
        # @return [void]
        def text_list(attr, child)
          define_method(:"#{attr}_from_xml") do |model, nodes|
            model.public_send(:"#{attr}=", XmlTextList.texts(nodes, child))
          end
          define_method(:"#{attr}_to_xml") { |_model, _parent, _doc| nil }
        end

        # @param attr [Symbol] an attribute declared with {text_list}
        # @return [Hash] the `with:` option for map_element
        def self.handlers(attr)
          { with: { from: :"#{attr}_from_xml", to: :"#{attr}_to_xml" } }
        end

        # @param nodes [Array, Object] the wrapper element(s) Lutaml hands over
        # @param child [String] the repeated child element name
        # @return [Array<String>] the stripped, non-empty child texts
        def self.texts(nodes, child)
          Array(nodes).flat_map(&:children)
                      .select { |node| node.name == child }
                      .map { |node| node.text.to_s.strip }
                      .reject(&:empty?)
        end
      end
    end
  end
end
