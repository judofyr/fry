require_relative 'expr'

class ClosureVariable
  attr_accessor :symbol_name
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def compile_expr
    LoadClosureExpr.new("this", self)
  end

  def static?
    false
  end
end

class LoadClosureExpr < Expr
  def initialize(env_symbol, variable)
    @env_symbol = env_symbol
    @variable = variable
  end

  def typeof
    @variable.type
  end

  def to_js(block)
    "%s.%s" % [@env_symbol, @variable.symbol_name]
  end
end

