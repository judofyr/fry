require_relative 'expr_compiler'
require_relative 'backend'

class Function < Expr
  attr_reader :symbol, :scope

  def initialize(symbol)
    @symbol = symbol

    @scope = SymbolScope.new(symbol.file.scope)

    w = symbol.new_walker
    w.take!(:func)
    @name = w.read_ident # func_name

    @params = []
    while w.tag_name == :field_name
      param_name = w.read_ident
      w.take!(:field_type)
      type = ExprCompiler.compile(w, @scope)
      param = Variable.new(param_name)
      param.assign_type(type)
      @params << param
      @scope[param_name] = param
    end

    backend = @symbol.compiler.backend
    @js = backend.new_function(@name, @params)
    @body_scope = SymbolScope.new(@scope)
    @body_scope.target = @js.root_block

    w.take!(:func_body)

    ExprCompiler.compile_block(w, @body_scope)

    w.take!(:block_end)
    w.take!(:func_end)
  end

  def symbol_name
    @js.symbol
  end

  def call(args)
    arglist = @params.map do |param|
      args[param.name] or raise "Missing param: #{param.name}"
    end
    CallExpr.new(self, arglist)
  end
end

