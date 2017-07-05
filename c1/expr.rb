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

  def prim(block)
    "#{to_js(block)}[0]"
  end

  def insert_into(block)
    code = to_js(block)
    block.frame << "#{code};"
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

  def prim(block)
    "#{@value}"
  end

  def to_js(block)
    "[#{@value}]"
  end
end

class VoidExpr < Expr
  def typeof
    Types.void
  end

  def to_js(block)
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

  def to_js(block)
    @variable.symbol_name
  end
end

## Functions

class ReturnExpr < Expr
  def initialize(expr)
    @expr = expr
  end

  def insert_into(block)
    value = @expr.to_js(block)
    if block.return_suspends?
      block.frame << "return ret(#{value});"
    else
      block.frame << "return #{value};"
    end
  end
end

class CallExpr < Expr
  def initialize(func, arglist)
    @func = func
    @arglist = arglist
  end

  def js_arglist(block)
    @arglist
      .zip(@func.params)
      .select { |(arg, param)| param.is_a?(Variable) }
      .map { |(arg, param)| arg }
      .map { |e| e.to_js(block) }
  end

  def to_js(block)
    args = js_arglist(block)

    if @func.throws
      if !block.throwable
        raise "cannot throw here"
      end

      args << "exc"
    end

    before = block.frame

    if @func.suspends
      after = block.new_frame
      args << after
    end

    code = "%s(%s)" % [@func.symbol_name, args.join(", ")]

    if @func.suspends
      var = block.new_var("val")
      before << "return #{code};"
      after << "#{var} = val"
      var
    elsif @func.throws
      var = block.new_var("val")
      before << "#{var} = #{code};"
      # This is only in case we have a throwable inside a
      # suspendable block.
      before << "if (#{var} === FryDidThrow) return;"
      var
    else
      code
    end
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

  def throws?
    @func.throws
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
  def prim(block)
    "(%s %s %s)" % [@args[-2].prim(block), op, @args[-1].prim(block)]
  end

  def to_js(block)
    "[%s %s %s]" % [@args[-2].prim(block), op, @args[-1].prim(block)]
  end
end

class AddExpr < BuiltinExpr
  include BinaryExpr
  def op; "+" end
end

class SubExpr < BuiltinExpr
  include BinaryExpr
  def op; "-" end
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
  def to_js(block)
    type_expr, loc, value = *@args
    type = type_expr.constant_value(TypeConstant)
    if type.is_a?(ConstructedType)
      type.constructor.fields.size.times.map do |idx|
        "%s[%d] = %s[%d];" % [loc.to_js(block), idx, value.to_js(block), idx]
      end.join(" ")
    else
      "%s = %s;" % [loc.prim(block), value.prim(block)]
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

  def to_js(block)
    "[%s]" % @values.map { |f| f.to_js(block) }.join(", ")
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

  def to_js(block)
    "%s[%d]" % [@base.to_js(block), @idx]
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

  def to_js(block)
    "[%s, %s]" % [@tag, @value.to_js(block)]
  end
end

class UnionFieldExpr < FieldExpr
  def error
    "(function() { throw new Error('wrong tag') })()"
  end

  def to_js(block)
    "(tmp = #{@base.to_js(block)})[0] == #{@idx} ? tmp[1] : #{error}"
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

  def prim(block)
    "%s[0] == %d" % [@base.to_js(block), @idx]
  end

  def to_js(block)
    "[#{prim}]"
  end
end


## Variables

class AssignExpr < Expr
  def initialize(variable, value)
    @variable = variable
    @value = value
  end

  def insert_into(block)
    code = "#{@variable.symbol_name} = #{@value.to_js(block)};"
    block.frame << code
  end
end

## Branches

class BranchExpr < Expr
  def initialize(cases)
    @cases = cases
  end

  def insert_into(block)
    sus = suspends?

    # First evaluate all the conds

    conds = @cases.map { |cond, branch| cond && cond.prim(block) }

    before = block.frame

    if sus
      after = block.new_frame
    end

    # TODO: async!
    code = @cases.each_with_index.map do |(cond, branch), idx|
      if sus
        body = "{\n#{branch.target.suspendable_function}(#{after})\n}"
      else
        body = "{\n#{branch.target.body}\n}"
      end

      if !cond
        " else #{body}"
      elsif idx.zero?
        "if (#{conds[idx]}) #{body}"
      else
        " else if (#{conds[idx]}) #{body}"
      end
    end.join

    if sus && !complete?
      code << " else { #{after}() }"
    end

    before << code
  end

  def suspends?
    @cases.any? { |cond, branch| branch.target.suspends? }
  end

  def complete?
    cond, branch = *@cases.last
    cond.nil?
  end
end

class ThrowExpr < BuiltinExpr
  def insert_into(block)
    if !block.throwable
      raise "cannot throw here"
    end
    block.frame << "return exc(new Error);"
  end
end

class TryBlockExpr < Expr
  def initialize(body, handler)
    @body = body
    @handler = handler
  end

  def insert_into(block)
    if block.suspends?
      return async_insert_into(block)
    end

    before = block.frame
    try = "try { #{@body.target.body} }"
    cat = "catch (err) { #{@handler.target.body} }"
    before << "(function(exc) { #{try} #{cat} })(FryThrow)"
  end

  def async_insert_into(block)
    before = block.frame
    after = block.new_frame
    before << "function exc(err) { #{@handler.target.suspendable_function}(#{after}); return FryDidThrow; }"
    before << "#{@body.target.suspendable_function}(#{after})"
  end
end

class CoroExpr < BuiltinExpr
  def to_js
    "FryCoroCurrent"
  end
end

class SuspendExpr < BuiltinExpr
  def insert_into(block)
    before = block.frame
    after = block.new_frame
    code = "FryCoroCurrent.cont = #{after};FryCoroCurrent = null;"
    before << code
  end
end

class ResumeExpr < BuiltinExpr
  def insert_into(block)
    code = "FryCoroResume(#{@args[0].to_js(block)});"
    block.frame << code
  end
end

class SpawnExpr < Expr
  def initialize(body)
    @body = body
  end

  def to_js(block)
    cont = "function() { #{@body.target.suspendable_function}(FryCoroComplete) }"
    "{cont:#{cont}}"
  end
end

