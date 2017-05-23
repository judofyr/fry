class SymbolGenerator
  attr_reader :symbols

  def initialize(prefix)
    @prefix = prefix
    @counts = Hash.new { |h, k| h[k] = 0 }
  end

  def symbol_for(name, num)
    if num == 0
      "#{@prefix}#{name}"
    else
      "#{@prefix}#{name}_#{num}"
    end
  end

  def create(name)
    num = @counts[name]
    @counts[name] += 1
    symbol_for(name, num)
  end

  def each
    @counts.each do |name, max|
      max.times { |num| yield symbol_for(name, num) }
    end
    self
  end

  def to_a
    res = []
    each { |sym| res << sym }
    res
  end
end

class JSBackend
  def initialize
    @funcgen = SymbolGenerator.new("$")
    @functions = []
  end

  def new_function(name, params)
    symbol = @funcgen.create(name)
    func = JSFunction.new(symbol, params)
    @functions << func
    func
  end

  def to_s
    @functions.map(&:to_s).join("\n\n")
  end
end

class JSFunction
  attr_reader :symbol, :vargen

  def initialize(symbol, params)
    @symbol = symbol
    @params = params
    @params.each do |param|
      param.symbol_name = param.name
    end
    @vargen = SymbolGenerator.new("_")
  end

  def root_block
    @root_block ||= JSBlock.new(self)
  end

  def var_decl
    vars = @vargen.to_a
    if vars.any?
      "var #{vars.join(", ")};\n"
    else
      ""
    end
  end

  def to_s
    "function #@symbol(#{@params.map(&:name).join(", ")}) {\n" +
      var_decl +
      @root_block.to_js +
    "\n}"
  end
end

class JSBlock
  def initialize(js_function)
    @js_function = js_function
    @code = []
  end

  def new_block
    JSBlock.new(@js_function)
  end

  def register_variable(var)
    var.symbol_name = @js_function.vargen.create(var.name)
    nil
  end

  def <<(expr)
    @code << "#{expr.to_js};"
  end

  def to_js
    @code.join("\n")
  end
end

