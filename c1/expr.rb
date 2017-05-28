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
  
  def any_trait
    @any_trait ||= AnyTrait.new
  end

  def num_trait
    @num_trait ||= NumTrait.new
  end

  def int_trait
    @int_trait ||= IntTrait.new
  end
end

class Expr
  def typeof
    Types.void
  end

  def generic?
    false
  end

  def prim
    "#{to_js}[0]"
  end
end

## Types

class Type < Expr
  def compile_expr
    self
  end

  def typeof
    Types.type
  end
end

class IntType < Type
  def initialize(bitsize)
    @bitsize = bitsize
  end
end

class VoidType < Type
end

class TypeType < Type
end

class Trait < Type
  def matches?(type)
    false
  end
end

class AnyTrait < Trait
  def matches?(type)
    true
  end
end

class NumTrait < Trait
  def matches?(type)
    type.is_a?(IntType)
  end
end

class IntTrait < Trait
  def matches?(type)
    type.is_a?(IntType)
  end
end

## Literals

class IntegerExpr < Expr
  def initialize(value)
    @value = value
  end

  def typeof
    Types.ints[32]
  end

  def prim
    "#{@value}"
  end

  def to_js
    "[#{@value}]"
  end
end

## Functions

class ReturnExpr < Expr
  def initialize(expr)
    @expr = expr
  end

  def to_js
    "return #{@expr.to_js}"
  end
end

class CallExpr < Expr
  def initialize(func, arglist)
    @func = func
    @arglist = arglist
  end

  def to_js
    # TODO: use the @func's concrete params
    args = @arglist
      .select { |arg| !arg.typeof.is_a?(TypeType) }
      .map(&:to_js)
      .join(", ")

    "%s(%s)" % [@func.symbol_name, args]
  end

  def typeof
    type = @func.return_type
    # TODO: this needs to be handled better...
    type = type.variable if type.is_a?(VariableExpr)
    if idx = @func.params.index(type)
      @arglist[idx]
    else
      type
    end
  end
end

module BinaryExpr
  def initialize(func, args)
    @func = func
    @args = args
  end

  def typeof
    @args[0]
  end

  def prim
    "(%s %s %s)" % [@args[1].prim, op, @args[2].prim]
  end

  def to_js
    "[%s %s %s]" % [@args[1].prim, op, @args[2].prim]
  end
end

class AddExpr < Expr
  include BinaryExpr
  def op; "+" end
end

class SubExpr < Expr
  include BinaryExpr
  def op; "+" end
end

class MulExpr < Expr
  include BinaryExpr
  def op; "*" end
end

class TypeCastExpr < Expr
  def initialize(expr, type)
    @expr = expr
    @type = type
  end

  def typeof
    @type
  end

  def to_js
    @expr.to_js
  end
end

class GenericExpr < Expr
  def initialize(expr, mapping)
    @expr = expr
    @mapping = mapping
  end

  def typeof
    @type ||= GenericExpr.new(@expr.typeof, @mapping)
  end

  def resolve(expr)
    type = expr.typeof
    if mapped = @mapping[type]
      TypeCastExpr.new(expr, mapped)
    elsif type.generic?
      GenericExpr.new(expr, @mapping)
    else
      expr
    end
  end

  def call(args)
    resolve(@expr.call(args))
  end

  def field(expr, name)
    @mapping.each do |param, expr|
      if param.name == name
        return expr
      end
    end
    resolve(@expr.field(expr, name))
  end

  def to_js
    @expr.to_js
  end
end

class StructLiteral < Expr
  def initialize(struct, values)
    @struct = struct
    @values = values
  end

  def typeof
    @struct
  end

  def to_js
    "[%s]" % @values.map { |f| f.to_js }.join(", ")
  end
end

class FieldExpr < Expr
  def initialize(base, idx, type)
    @base = base
    @idx = idx
    @type = type
  end

  def typeof
    @type
  end

  def to_js
    "%s[%d]" % [@base.to_js, @idx]
  end
end

## Variables

class VariableExpr < Expr
  attr_reader :variable

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

## Branches

class BranchExpr < Expr
  def initialize(cond, tbranch)
    @cond = cond
    @tbranch = tbranch
  end

  def to_js
    "if (#{@cond.to_js}) {\n#{@tbranch.target.to_js}\n}"
  end
end

