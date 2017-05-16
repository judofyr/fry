module Parser
  class Input
    attr_reader :data, :pos, :tags

    Tag = Struct.new(:position, :name)

    def initialize(data, pos = 0, tags = [])
      @data = data
      @pos = pos
      @tags = tags

      # HACK: This is a very ugly way to find the "latest" parse error
      if $max and @pos > $max
        $max = @pos
      end
    end

    def eos?
      @pos == @data.size
    end

    def advance(amount)
      Input.new(@data, @pos + amount, @tags)
    end

    def tag(name)
      Input.new(@data, @pos, @tags + [Tag.new(@pos, name)])
    end
  end

  class Parser
    def >>(other)
      ConcatParser.new(self, other)
    end

    def /(other)
      ChoiceParser.new(self, other)
    end

    def not
      NotParser.new(self)
    end

    def repeat # zero or more times
      RepeatParser.new(self)
    end

    def many # one or more times
      self >> self.repeat
    end

    def maybe # zero or one
      MaybeParser.new(self)
    end

    def join(by)
      self >> (by >> self).repeat
    end
  end

  class TagParser < Parser
    def initialize(tag)
      @tag = tag
    end

    def parse(input)
      input.tag(@tag)
    end
  end

  class AnyParser < Parser
    def parse(input)
      input.advance(1)
    end
  end

  class NotParser < Parser
    def initialize(parser)
      @parser = parser
    end

    def parse(input)
      if @parser.parse(input)
        nil
      else
        input
      end
    end
  end

  class MaybeParser < Parser
    def initialize(parser)
      @parser = parser
    end

    def parse(input)
      @parser.parse(input) or input
    end
  end

  class ExactParser < Parser
    def initialize(text)
      @text = text
    end

    def parse(input)
      @text.size.times do |idx|
        if input.data[input.pos+idx] != @text[idx]
          return
        end
      end
      input.advance(@text.size)
    end
  end

  class CharParser < Parser
    def initialize(char)
      @char = char
    end

    def matches?(char)
      return false if char.nil?
      return true if char == @char

      case @char
      when :space
        char == " "
      when :newline
        char == "\n"
      when :digit
        char >= "0" and char <= "9"
      when :ident
        char =~ /[A-Za-z0-9-]/
      when :identfst
        char =~ /[A-Za-z]/
      else
        false
      end
    end

    def parse(input)
      if matches?(input.data[input.pos])
        input.advance(1)
      end
    end
  end

  class RepeatParser < Parser
    def initialize(parser)
      @parser = parser
    end

    def parse(input)
      while next_input = @parser.parse(input)
        input = next_input
      end
      input
    end
  end

  class ConcatParser < Parser
    def initialize(left, right)
      @left = left
      @right = right
    end

    def parse(input)
      if input = @left.parse(input)
        @right.parse(input)
      end
    end
  end

  class ChoiceParser < Parser
    def initialize(left, right)
      @left = left
      @right = right
    end

    def parse(input)
      @left.parse(input) or @right.parse(input)
    end
  end

  class LazyParser < Parser
    def initialize(&blk)
      @blk = blk
    end

    def parser
      @parser ||= @blk.call
    end

    def parse(input)
      parser.parse(input)
    end
  end

  class Grammar
    def initialize(&blk)
      instance_eval(&blk)
    end

    def str(string)
      ExactParser.new(string)
    end

    def any
      AnyParser.new
    end

    def tag(name)
      TagParser.new(name)
    end

    def char(char)
      CharParser.new(char)
    end

    def let(name, &blk)
      parser = LazyParser.new(&blk)
      define_singleton_method(name) { parser }
      parser
    end
  end
end

