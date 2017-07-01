class ValueEquality < Module
  def initialize(&blk)
    super do
      define_method(:_values, &blk)

      def ==(other)
        other.is_a?(self.class) and other._values == _values
      end

      def hash
        _values.hash
      end

      alias eql? ==
    end
  end
end

