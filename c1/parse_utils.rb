module Parser
  class Walker
    attr_reader :idx

    def initialize(input, idx = 0)
      @input = input
      @idx = idx
    end

    def tag
      @input.tags[@idx]
    end

    def tag_name
      tag.name
    end

    def position
      tag.position
    end

    def next
      if done?
        raise "Walked past file"
      end
      @idx += 1
      self
    end
    
    def take(name)
      if tag_name == name
        self.next
        true
      else
        false
      end
    end

    def take!(name)
      raise "expected #{name}, not #{tag_name}" unless take(name)
    end

    def done?
      @idx == @input.tags.size
    end

    def read_ident
      fst = position
      self.next
      lst = position
      self.next
      @input.data[fst...lst]
    end

    def read_string
      raise "Not a string" unless tag_name == :string
      fst = position+1
      self.next
      raise "TODO: escape" unless tag_name == :string_end
      lst = position-1
      self.next
      @input.data[fst...lst]
    end

    def read_number
      fst = position
      self.next until tag_name == :number_end
      lst = position
      self.next
      @input.data[fst...lst].to_i
    end
  end
end

