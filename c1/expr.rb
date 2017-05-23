module Types
  module_function

  def ints
    @ints ||= Hash.new { |h, k| h[k] = IntType.new(k) }
  end

  def type
    @type ||= TypeType.new
  end

  def void
    @void ||= VoidType.new
  end
end

class Expr
  def typeof
    Types.void
  end
end

## Types

class Type < Expr
  def compile_expr
    self
  end
end

class IntType < Type
  def initialize(bitsize)
    @bitsize = bitsize
  end
end

class VoidType < Type
end

## Literals

class IntegerExpr < Expr
  def initialize(value)
    @value = value
  end

  def typeof
    Types.ints[32]
  end

  def to_js
    "[#{@value}]"
  end
end

## Functions

class CallExpr < Expr
  def initialize(func, arglist)
    @func = func
    @arglist = arglist
  end

  def to_js
    "%s(%s)" % [@func.symbol_name, @arglist.map(&:to_js).join(", ")]
  end
end

## Variables

class VariableExpr < Expr
  def initialize(variable)
    @variable = variable
  end

  def typeof
    @variable.type
  end

  def to_js
    @variable.symbol_name
  end
end

class AssignExpr < Expr
  def initialize(variable, value)
    @variable = variable
    @value = value
  end

  def to_js
    "#{@variable.symbol_name} = #{@value.to_js}"
  end
end

