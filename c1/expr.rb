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
  
  def any
    @any ||= AnyTrait.new
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

class StructType < Type
  def initialize(struct, genargs)
    @struct = struct
    @genargs = genargs
  end

  def field(expr, name)
    @struct.fields.each_with_index do |(field_name, type), idx|
      if field_name == name
        if type.is_a?(Genparam)
          genidx = @struct.genparams.index(type)
          type = @genargs[genidx]
        end

        return FieldExpr.new(expr, idx, type)
      end
    end
    raise "no such field: #{name}"
  end
end

class Trait < Type
end

class AnyTrait < Trait
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

class GencallExpr < Expr
  def initialize(struct, args)
    @struct = struct
    @args = args

    if @struct.genparams.size != @args.size
      # TODO: typecheck (maybe one frame up)
      raise "gencall params doesn't match up"
    end
  end

  def call(args)
    mapping = {}

    @struct.genparams.zip(@args) do |param, arg|
      mapping[param] = arg
    end

    fieldlist = @struct.fields.map do |name, type|
      arg = args.fetch(name)
      if !ExprCompiler.typecheck(arg, type, mapping)
        raise "Couldn't typecheck"
      end
      arg
    end

    StructLiteral.new(@struct, @args, fieldlist)
  end
end

class StructLiteral < Expr
  def initialize(struct, genargs, fields)
    @struct = struct
    @genargs = genargs
    @fields = fields
    @type = @struct.type_for(genargs)
  end

  def typeof
    @type
  end

  def to_js
    "[%s]" % @fields.map { |f| f.to_js }.join(", ")
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

