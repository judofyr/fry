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

  def new_function(name, *args)
    symbol = @funcgen.create(name)
    func = JSFunction.new(symbol, *args)
    @functions << func
    func
  end

  JS_INIT = <<~JS
    var FryCoroCurrent;
    function FryCoroDead() {
      throw new Error('resuming dead coro');
    }
    function FryCoroComplete() {
      FryCoroCurrent.cont = FryCoroDead;
    }
    function FryCoroResume(coro) {
      var old = FryCoroCurrent;
      if (old === coro) {
        throw new Error('resuming active coro');
      }
      FryCoroCurrent = coro;
      FryCoroCurrent.cont(FryCoroComplete);
      FryCoroCurrent = old;
    }
    function FryCoroWrap(cont) {
      var curr = FryCoroCurrent;
      curr.cont = cont;
      return function() { FryCoroResume(curr); }
    }
  JS

  def to_s
    JS_INIT +
    @functions.map(&:to_s).join("\n\n")
  end
end

class JSFunction
  attr_reader :symbol, :vargen, :return_type, :suspendable

  def initialize(symbol, params, return_type, suspendable: false)
    @symbol = symbol
    @params = params
    @params.each do |param|
      param.symbol_name = param.name
    end
    @vargen = SymbolGenerator.new("_")
    @return_type = return_type
    @suspendable = suspendable
  end

  def root_block
    @root_block ||= JSBlock.new(self, suspendable: suspendable)
  end

  def var_decl
    vars = @vargen.to_a
    if vars.any?
      "var #{vars.join(", ")};\n"
    else
      ""
    end
  end

  def function_decl
    param_string = @params.map(&:name).join(", ")
    "function #@symbol(#{param_string}) {\n" +
      var_decl +
      @root_block.to_js +
    "\n}"
  end

  def suspendable_function_decl
    param_string = [*@params.map(&:name), "cont"].join(", ")
    "function #@symbol(#{param_string}) {\n" +
      var_decl +
      @root_block.suspendable_body +
    "\n}"
  end

  def to_s
    if @suspendable
      suspendable_function_decl
    else
      function_decl
    end
  end
end

class CodeContext
  attr_reader :symbol, :code

  def initialize(symbol)
    @symbol = symbol
    @code = [] 
  end

  def <<(code)
    @code << code
  end

  def body
    @code.join("\n")
  end

  def to_js
    "function #{@symbol}() {\n#{body}\n}"
  end

  def to_s
    "#{@symbol}"
  end
end

class JSBlock
  attr_accessor :suspendable

  def initialize(js_function, parent: nil, suspendable: false)
    @js_function = js_function
    @parent = parent

    @suspendable = suspendable
    @contexts = []
  end

  def new_block
    JSBlock.new(@js_function, suspendable: @suspendable)
  end

  def return_type
    @js_function.return_type
  end

  def register_variable(var)
    var.symbol_name = @js_function.vargen.create(var.name)
    nil
  end

  def new_context
    CodeContext.new(@js_function.vargen.create("cb")).tap do |ctx|
      @contexts << ctx
    end
  end

  def current_context
    @contexts.last || new_context
  end

  def cont
    new_context.symbol
  end

  def add_raw(js)
    current_context << js
  end

  def <<(expr)
    ctx = current_context
    if suspendable
      ctx << expr.to_async_js(self)
    else
      ctx << expr.to_js
    end
  end

  def complete
    if suspendable
      current_context << "cont()"
    end
  end

  def suspendable_body
    code = @contexts[1..-1].map(&:to_js)
    code << @contexts[0].body
    code.join("\n")
  end

  def suspendable_function
    "(function(cont) { #{suspendable_body} })"
  end

  def to_js
    if suspendable
      suspendable_function
    elsif @contexts.any?
      @contexts[0].body
    else
      ""
    end
  end
end

