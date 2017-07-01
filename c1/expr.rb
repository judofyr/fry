require_relative 'type'
require_relative 'constant'

class Expr
  def typeof
    Types.void
  end

  def constant
    # Nope. We're not a constant
    nil
  end

  def constant_value(klass)
    if (c = constant).is_a?(klass)
      c.value
    end
  end

  def prim
    "#{to_js}[0]"
  end
end

## Types

class TypeExpr < Expr
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def compile_expr
    self
  end

  def constant
    @constant ||= TypeConstant.new(@type)
  end

  def typeof
    Types.type
  end
end

class TypeConstructorExpr < TypeExpr
  def constant
    @constant ||= TypeConstructorConstant.new(@type)
  end
end

## Literals

class IntExpr < Expr
  def initialize(value)
    @value = value
    @type = Types.ints[32]
  end

  def constant
    @constant ||= IntConstant.new(@value)
  end

  def typeof
    @type
  end

  def prim
    "#{@value}"
  end

  def to_js
    "[#{@value}]"
  end
end

class VoidExpr < Expr
  def typeof
    Types.void
  end

  def to_js
    "null"
  end
end

class LoadExpr < Expr
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

## Functions

class ReturnExpr < Expr
  def initialize(expr)
    @expr = expr
  end

  def to_js
    "return #{@expr.to_js};"
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
      .zip(@func.params)
      .select { |(arg, param)| param.is_a?(Variable) }
      .map { |(arg, param)| arg }
      .map(&:to_js)
      .join(", ")

    "%s(%s)" % [@func.symbol_name, args]
  end

  def resolve_type(type)
    if idx = @func.params.index(type)
      @arglist[idx].constant_value(TypeConstant)
    end
  end

  def typeof
    type = @func.return_type
    ExprCompiler.resolve_type_recursive(type, self)
  end
end

class BuiltinExpr < Expr
  def initialize(func, args)
    @func = func
    @args = args
  end

  def resolve_type(type)
    if idx = @func.params.index(type)
      @args[idx].constant_value(TypeConstant)
    end
  end

  def typeof
    type = @func.return_type
    ExprCompiler.resolve_type_recursive(type, self)
  end
end

module BinaryExpr
  def prim
    "(%s %s %s)" % [@args[-2].prim, op, @args[-1].prim]
  end

  def to_js
    "[%s %s %s]" % [@args[-2].prim, op, @args[-1].prim]
  end
end

class AddExpr < BuiltinExpr
  include BinaryExpr
  def op; "+" end
end

class SubExpr < BuiltinExpr
  include BinaryExpr
  def op; "+" end
end

class MulExpr < BuiltinExpr
  include BinaryExpr
  def op; "*" end
end

class AndExpr < BuiltinExpr
  include BinaryExpr
  def op; "&&" end
end

class OrExpr < BuiltinExpr
  include BinaryExpr
  def op; "||" end
end

class SetExpr < BuiltinExpr
  def to_js
    type_expr, loc, value = *@args
    type = type_expr.constant_value(TypeConstant)
    if type.is_a?(ConstructedType)
      type.constructor.fields.size.times.map do |idx|
        "%s[%d] = %s[%d];" % [loc.to_js, idx, value.to_js, idx]
      end.join(" ")
    else
      "%s = %s;" % [loc.prim, value.prim]
    end
  end
end

class StructLiteral < Expr
  def initialize(type, values)
    @type = type
    @values = values
  end

  def typeof
    @type
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

class UnionLiteral < Expr
  def initialize(type, tag, value)
    @type = type
    @tag = tag
    @value = value
  end

  def typeof
    @type
  end

  def to_js
    "[%s, %s]" % [@tag, @value.to_js]
  end
end

class UnionFieldExpr < FieldExpr
  def error
    "(function() { throw new Error('wrong tag') })()"
  end

  def to_js
    "(tmp = #{@base.to_js})[0] == #{@idx} ? tmp[1] : #{error}"
  end
end

class UnionFieldPredicateExpr < Expr
  def initialize(base, idx)
    @base = base
    @idx = idx
  end

  def typeof
    Types.bool
  end

  def prim
    "%s[0] == %d" % [@base.to_js, @idx]
  end

  def to_js
    "[#{prim}]"
  end
end


## Variables

class AssignExpr < Expr
  def initialize(variable, value)
    @variable = variable
    @value = value
  end

  def to_js
    "#{@variable.symbol_name} = #{@value.to_js};"
  end
end

## Branches

class BranchExpr < Expr
  def initialize(cases)
    @cases = cases
  end

  def to_js
    @cases.each_with_index.map do |(cond, branch), idx|
      body = "{\n#{branch.target.to_js}\n}"
      if !cond
        " else #{body}"
      elsif idx.zero?
        "if (#{cond.prim}) #{body}"
      else
        " else if (#{cond.prim}) #{body}"
      end
    end.join
  end
end

