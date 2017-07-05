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
    function FryThrow(err) {
      throw err;
    }
    var FryDidThrow = {};
  JS

  def to_s
    JS_INIT +
    @functions.map(&:to_s).join("\n\n")
  end
end

class JSFunction
  attr_reader :symbol, :vargen, :return_type, :suspends, :throws

  def initialize(symbol, params, return_type, suspends: false, throws: false)
    @symbol = symbol
    @params = params
    @params.each do |param|
      param.symbol_name = param.name
    end
    @vargen = SymbolGenerator.new("_")
    @return_type = return_type
    @suspends = suspends
    @throws = throws

    @param_names = @params.map(&:name)

    if @throws
      root_block.throwable = true
      @param_names << "exc"
    end

    if @suspends
      root_block.suspendable = true
      @param_names << "ret"
    end
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

  def param_string
    @param_names.join(", ")
  end

  def function_decl
    "function #@symbol(#{param_string}) {\n" +
      var_decl +
      @root_block.body +
    "\n}"
  end

  def suspendable_function_decl
    "function #@symbol(#{param_string}) {\n" +
      var_decl +
      "var cont = ret;\n" +
      @root_block.suspendable_body +
    "\n}"
  end

  def to_s
    if @suspends
      suspendable_function_decl
    else
      function_decl
    end
  end
end

class Frame
  attr_reader :symbol
  attr_accessor :next_frame_symbol

  def initialize(symbol)
    @symbol = symbol
    @next_frame_symbol = "cont"
    @code = [] 
  end

  def <<(code)
    @code << code
  end

  def body
    @code.join("\n")
  end

  def to_function(extra = "")
    "function #{@symbol}(val) {\n#{body} #{extra} \n}"
  end

  def to_s
    @symbol
  end
end

class JSBlock
  attr_accessor :suspendable, :throwable

  def initialize(js_function, parent: nil)
    @js_function = js_function
    @parent = parent

    @suspendable = parent ? parent.suspendable : false
    @throwable = parent ? parent.throwable : false
    @frames = []

    new_frame
  end

  def new_block
    JSBlock.new(@js_function, parent: self)
  end

  def return_type
    @js_function.return_type
  end

  def register_variable(var)
    var.symbol_name = @js_function.vargen.create(var.name)
    nil
  end

  def new_var(name)
    @js_function.vargen.create(name)
  end

  def frame
    @frames.last
  end

  def new_frame
    if @frames.size > 1 and !suspendable
      raise "not in a suspendable context"
    end

    symbol = @js_function.vargen.create("frame")
    Frame.new(symbol).tap do |f|
      @frames << f
    end
  end

  def suspendable_body
    fst, *rst = @frames

    if rst.empty?
      fst.body + "\n" + "return cont()"
    else
      lst = rst.pop
      code = rst.map(&:to_function)
      code << lst.to_function("return cont()")
      code << fst.body
      code.join("\n")
    end
  end

  def suspendable_function
    "(function(cont) { #{suspendable_body} })"
  end

  def suspends?
    @frames.size > 1
  end

  def return_suspends?
    @js_function.suspends
  end

  def body
    if @frames.size != 1
      raise "this block suspends"
    end
    @frames[0].body
  end
end

