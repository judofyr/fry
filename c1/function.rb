require_relative 'expr_compiler'
require_relative 'backend'

class Function < Expr
  attr_reader :symbol, :scope, :return_type, :params

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

    backend = @symbol.compiler.backend
    concrete_params = @params.select { |p| !p.type.is_a?(Trait) }
    @js = backend.new_function(@name, concrete_params)
    @body_scope = SymbolScope.new(@scope)
    @body_scope.target = @js.root_block

    w.take!(:func_body)

    ExprCompiler.compile_block(w, @body_scope)

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

    CallExpr.new(self, arglist)
  end
end

