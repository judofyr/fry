class Scope
  attr_reader :parent
  attr_accessor :target

  def initialize(parent = nil, target = nil)
    @parent = parent
    @target = target
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

  def new_child(klass = SymbolScope)
    klass.new(self, target && target.new_block)
  end
end

class SymbolScope < Scope
  def initialize(*)
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

require_relative 'expr'

class ImplementScope < Scope
  attr_accessor :decl
  attr_accessor :type

  class SelfExpr < Expr
    def initialize(type)
      @type = type
    end

    def compile_expr
      self
    end

    def typeof
      @type
    end

    def to_js(block)
      "this"
    end
  end

  def lookup(key)
    if key == "self"
      return SelfExpr.new(type)
    end

    decl.params.each do |param|
      if param.name == key
        return param
      end
    end
    return nil
  end
end

require_relative 'closure'

class ClosureScope < Scope
  attr_accessor :env

  Local = Struct.new(:variable, :expr)

  def locals
    @locals ||= {}
  end

  def symgen
    @symgen ||= SymbolGenerator.new("")
  end

  def lookup(key)
    if local = locals[key]
      return locals.variable
    end

    value = env[key]
    if value.static?
      value
    else
      expr = value.compile_expr
      var = ClosureVariable.new(expr.typeof)
      var.symbol_name = symgen.create(key)
      locals[key] = Local.new(var, expr)
      value = var
    end
    value
  end
end

