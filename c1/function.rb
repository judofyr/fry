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
      type = ExprCompiler.compile(w, @scope)
      if param_name == "return"
        @return_type = type
      else
        param = Variable.new(param_name)
        param.assign_type(type)
        @params << param
        @scope[param_name] = param
      end
    end

    if w.take(:func_body)
      backend = @symbol.compiler.backend
      concrete_params = @params.select { |p| !p.type.is_a?(Trait) }
      @js = backend.new_function(@name, concrete_params)
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

  def call(args)
    mapping = {}

    args.each do |name, expr|
      param = @params.detect { |p| p.name == name }
      raise "no such param: #{name}" unless param
      if !ExprCompiler.typecheck(expr, param.type, mapping)
        raise "type error"
      end
    end

    arglist = @params.map do |param|
      args[param.name] or
        mapping[param] or
        raise "Missing param: #{param.name}"
    end

    @call_class.new(self, arglist)
  end
end

