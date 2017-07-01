require 'set'
require_relative 'expr_compiler'
require_relative 'backend'

class Function < Expr
  attr_reader :symbol, :scope, :return_type, :params

  BUILTINS = {
    "add" => AddExpr,
    "sub" => SubExpr,
    "mul" => MulExpr,
    "and" => AndExpr,
    "or" => OrExpr,
    "set" => SetExpr,
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

    if w.take(:func_body)
      backend = @symbol.compiler.backend
      concrete_params = @params.select { |p| p.is_a?(Variable) }
      @js = backend.new_function(@name, concrete_params, @return_type)
      @body_scope = SymbolScope.new(@scope)
      @body_scope.target = @js.root_block
      @call_class = CallExpr
      ExprCompiler.compile_block(w, @body_scope)
    elsif w.take(:func_builtin)
      @call_class = BUILTINS.fetch(@name)
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

