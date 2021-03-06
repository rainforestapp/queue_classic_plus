module QueueClassicPlus
  # From https://github.com/apotonick/uber/blob/master/lib/uber/inheritable_attr.rb which is MIT license
  module InheritableAttribute
    def inheritable_attr(name)
      instance_eval %Q{
        def #{name}=(v)
          @#{name} = v
        end
        def #{name}
          return @#{name} if instance_variable_defined?(:@#{name})
          @#{name} = InheritableAttribute.inherit_for(self, :#{name})
        end
      }
    end

    def self.inherit_for(klass, name)
      return unless klass.superclass.respond_to?(name)

      value = klass.superclass.send(name) # could be nil.
      Clone.(value) # this could be dynamic, allowing other inheritance strategies.
    end

    class Clone
      # The second argument allows injecting more types.
      def self.call(value, uncloneable=uncloneable())
        uncloneable.each { |klass| return value if value.kind_of?(klass) }
        value.clone
      end

      def self.uncloneable
        tmp = [Symbol, TrueClass, FalseClass, NilClass]
        tmp += [Fixnum, Bignum] if RUBY_VERSION < '2.4.0'
        tmp
      end
    end
  end
end
