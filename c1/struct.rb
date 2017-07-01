require_relative 'expr'
require_relative 'type'

module GenSymbol
  def scope
    @scope ||= SymbolScope.new(file_scope)
  end

  def file_scope
    symbol.file.scope
  end

  def read_conparams(w)
    result = []
    while w.tag_name == :field_name
      param_name = w.read_ident
      w.take!(:field_type)
      expr = ExprCompiler.compile(w, file_scope)
      type = expr.constant_value(TypeConstant) or raise "not a type"
      if type.is_a?(TypeType)
        typevar = TypeVariable.new(param_name)
        expr = TypeExpr.new(typevar)
      else
        raise "only type supported"
      end
      result << typevar
      scope[param_name] = expr
    end
    result
  end

  def read_fields(w)
    result = []
    if w.take(:type_body)
      while w.tag_name == :field_name
        param_name = w.read_ident
        w.take!(:field_type)
        expr = ExprCompiler.compile(w, scope)
        type = expr.constant_value(TypeConstant) or raise "not a type"
        result << [param_name, type]
      end
    end
    result
  end
end

class StructConstructor
  attr_reader :name, :symbol, :conparams, :fields

  include GenSymbol

  def initialize(symbol)
    @symbol = symbol

    w = symbol.new_walker
    w.take!(:struct)
    @name = w.read_ident
    @conparams = read_conparams(w)
    @fields = read_fields(w)
    w.take!(:struct_end)
  end

  def inspect
    "#<struct:#{name}>"
  end

  def parse_args(args, type_resolver)
    @fields.map do |name, type|
      arg = args.fetch(name)
      if arg.typeof != (resolved = type_resolver[type])
        p [:actual, arg.typeof]
        p [:expected, resolved]
        raise "#{name}: type mismatch"
      end
      arg
    end
  end
  
  def field_expr(base, name)
    @fields.each_with_index do |(field_name, type), idx|
      if name == field_name
        return FieldExpr.new(base, idx, type)
      end
    end
    nil
  end
end

