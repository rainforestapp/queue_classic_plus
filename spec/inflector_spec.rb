require 'spec_helper'

module QueueClassicPlus
  describe Inflector do
    describe ".underscore" do
      {
        "foo" => "foo",
        "Foo" => "foo",
        "FooBar" => "foo_bar",
        "Foo::Bar" => "foo/bar"
      }.each do |word, expected|
        it "converst #{word} to #{expected}" do
          expect(described_class.underscore(word)).to eq(expected)
        end
      end
    end
  end
end
