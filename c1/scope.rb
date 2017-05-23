class Scope
  attr_reader :parent
  attr_accessor :target

  def initialize(parent = nil)
    @parent = parent
  end

  def [](key)
    scope = self
    while scope
      if sym = scope.lookup(key)
        return sym
      end
      scope = scope.parent
    end
    raise KeyError, "could not find symbol: #{key}"
  end
end

class SymbolScope < Scope
  def initialize(parent = nil)
    super
    @symbols = {}
  end

  def []=(key, value)
    @symbols[key] = value
  end

  def lookup(key)
    @symbols[key]
  end
end

class IncludeScope < Scope
  attr_accessor :included_files

  def lookup(key)
    included_files.each do |file|
      if sym = file.scope.lookup(key)
        return sym
      end
    end
    nil
  end
end

