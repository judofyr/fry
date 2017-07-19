require 'set'
require_relative 'expr_compiler'
require_relative 'backend'

class FunctionDecl
  attr_reader :name, :scope, :params, :return_type, :throws, :suspends, :js_body, :builtin

  def initialize(w, parent_scope)
    @scope = SymbolScope.new(parent_scope)
    @name = w.read_ident # func_name
    @return_type = Types.void

    @params = []
    while w.tag_name == :field_name
      param_name = w.read_ident
      w.take!(:field_type)
      expr = ExprCompiler.compile(w, @scope)
      type = expr.constant_value(TypeConstant)
      if param_name == "return"
        @return_type = type
      else
        if !type.is_a?(TypeType)
          param = Variable.new(param_name)
          param.assign_type(type)
          param_symbol = param
        else
          param = TypeVariable.new(param_name)
          param_symbol = TypeExpr.new(param)
        end
        @params << param
        @scope[param_name] = param_symbol
      end
    end

    @suspends = false
    @throws = false

    while w.tag_name == :attr
      case attr_name = w.read_ident
      when "builtin"
        @builtin = true
      when "suspends"
        @suspends = true
      when "throws"
        @throws = true
      when "js"
        w.take!(:attr_value)
        @js_body = w.read_string
      else
        raise "Unknown attribute: #{attr_name}"
      end
    end

  end

  TYPE_INFER_PRECEDENCE = Hash.new(100)
  TYPE_INFER_PRECEDENCE[TypeVariable] = 0

  def expand_args(args)
    found_types = Hash.new { |h, k| h[k] = Set.new }

    args.each do |arg_name, arg_expr|
      param = params.detect { |p| p.name == arg_name }
      raise "#{@name}: unknown param: #{arg_name}" if param.nil?
      
      if !param.is_a?(TypeVariable)
        found_types[param.type] << arg_expr.typeof
      end
    end

    # Complete type-inference
    params.each do |param|
      if !args.has_key?(param.name)
        types = found_types[param]
        inferred = types.min_by { |t| TYPE_INFER_PRECEDENCE[t.class] }
        if inferred.nil?
          raise "cannot infer #{param.name}"
        end
        args[param.name] = TypeExpr.new(inferred)
      end
    end

    # TODO: type-check
    # TODO: implicit casting

    arglist = params.map { |p| args.fetch(p.name) }
  end
end

class Function < Expr
  attr_reader :symbol, :decl

  [:name, :scope, :params, :return_type, :throws, :suspends, :js_body, :builtin].each do |name|
    define_method(name) do @decl.send(name) end
  end

  BUILTINS = {
    "add" => AddExpr,
    "sub" => SubExpr,
    "mul" => MulExpr,
    "and" => AndExpr,
    "or" => OrExpr,
    "set" => SetExpr,
    "throw" => ThrowExpr,
    "coro" => CoroExpr,
    "suspend" => SuspendExpr,
    "resume" => ResumeExpr,
  }

  def initialize(symbol)
    @symbol = symbol

    w = symbol.new_walker
    w.take!(:func)
    @decl = FunctionDecl.new(w, symbol.file.scope)

    has_body = w.take(:func_body)
    if has_body || decl.js_body
      backend = @symbol.compiler.backend
      concrete_params = params.select { |p| p.is_a?(Variable) }
      @js = backend.new_function(name, concrete_params, return_type, suspends: suspends, throws: throws)
      if has_body
        @body_scope = SymbolScope.new(scope)
        @body_scope.target = @js.root_block
        ExprCompiler.compile_block(w, @body_scope)
      else
        raw_body = []
        if suspends
          raw_body << "cont = FryCoroWrap(cont);"
        end
        raw_body << js_body
        @js.root_block.frame << raw_body.join("\n")
      end
      @call_class = CallExpr
    elsif decl.builtin
      @call_class = BUILTINS.fetch(name)
    end

    w.take!(:func_end)
  end

  def symbol_name
    @js.symbol
  end

  def call(args)
    arglist = @decl.expand_args(args)
    @call_class.new(self, arglist)
  end
end

class Constructor < Expr
  attr_reader :functions

  def initialize(symbol)
    @symbol = symbol

    w = symbol.new_walker
    w.take!(:constructor)
    @decl = FunctionDecl.new(w, symbol.file.scope)
    @impls = {}

    trait = return_type.constructor
    if !trait.is_a?(TraitConstructor)
      raise "#{@decl.name}: trait return type required"
    end

    scope = @decl.scope
    @functions = {}

    @decl.params.each do |param|
      # ehm. this is a bit hacky
      param.symbol_name = "this.#{param.name}"
    end

    while w.take(:implement)
      name = w.read_ident
      decl = trait.functions.fetch(name)
      js = backend.new_function(name, decl.params, decl.return_type)
      impl_scope = ImplementScope.new(scope)
      impl_scope.decl = decl
      body_scope = SymbolScope.new(impl_scope)
      body_scope["self"] = SelfExpr.new(return_type)
      body_scope.target = js.root_block
      ExprCompiler.compile_block(w, body_scope)
      @functions[name] = js
    end
    w.take!(:constructor_end)
  end

  def backend
    @symbol.compiler.backend
  end

  def return_type
    @decl.return_type
  end

  def params
    @decl.params
  end

  def call(args)
    arglist = @decl.expand_args(args)
    ObjectExpr.new(self, arglist)
  end
end

