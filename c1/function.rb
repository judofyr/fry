require 'set'
require_relative 'expr_compiler'
require_relative 'backend'

class Function < Expr
  attr_reader :symbol, :scope, :name, :return_type, :params, :suspendable, :js_body

  BUILTINS = {
    "add" => AddExpr,
    "sub" => SubExpr,
    "mul" => MulExpr,
    "and" => AndExpr,
    "or" => OrExpr,
    "set" => SetExpr,
    "coro" => CoroExpr,
    "suspend" => SuspendExpr,
    "resume" => ResumeExpr,
  }

  def initialize(symbol)
    @symbol = symbol

    @scope = SymbolScope.new(symbol.file.scope)

    w = symbol.new_walker
    w.take!(:func)
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

    while w.tag_name == :attr
      case attr_name = w.read_ident
      when "builtin"
        @call_class = BUILTINS.fetch(@name)
      when "suspends"
        @suspends = true
      when "js"
        w.take!(:attr_value)
        @js_body = w.read_string
      else
        raise "Unknown attribute: #{attr_name}"
      end
    end

    has_body = w.take(:func_body)
    if has_body || @js_body
      backend = @symbol.compiler.backend
      concrete_params = @params.select { |p| p.is_a?(Variable) }
      @js = backend.new_function(@name, concrete_params, @return_type, suspends: @suspends)
      if has_body
        @body_scope = SymbolScope.new(@scope)
        @body_scope.target = @js.root_block
        ExprCompiler.compile_block(w, @body_scope)
      else
        raw_body = []
        if @suspendable
          raw_body << "cont = FryCoroWrap(cont);"
        end
        raw_body << @js_body
        @js.root_block.add_raw(raw_body.join("\n"))
      end
      @call_class = CallExpr
    end

    w.take!(:func_end)
  end

  def symbol_name
    @js.symbol
  end

  TYPE_INFER_PRECEDENCE = Hash.new(100)
  TYPE_INFER_PRECEDENCE[TypeVariable] = 0

  def call(args)
    found_types = Hash.new { |h, k| h[k] = Set.new }

    args.each do |arg_name, arg_expr|
      param = @params.detect { |p| p.name == arg_name }
      raise "unknown param: #{arg_name}" if param.nil?
      
      found_types[param.type] << arg_expr.typeof
    end

    # Complete type-inference
    @params.each do |param|
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

    arglist = @params.map { |p| args.fetch(p.name) }

    @call_class.new(self, arglist)
  end
end

