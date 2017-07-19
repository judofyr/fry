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
        if w.take(:field_type)
          expr = ExprCompiler.compile(w, scope)
          type = expr.constant_value(TypeConstant) or raise "not a type"
        else
          type = Types.void
        end
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

  def construct(constructed_type, args)
    values = @fields.map do |name, type|
      arg = args.fetch(name)
      resolved = ExprCompiler.resolve_type_recursive(type, constructed_type)
      if arg.typeof != resolved
        p [:actual, arg.typeof]
        p [:expected, resolved]
        raise "#{name}: type mismatch"
      end
      arg
    end
    StructLiteral.new(constructed_type, values)
  end

  def field_expr(base, name, is_predicate:)
    if is_predicate
      raise "? doesn't make sense on structs"
    end

    @fields.each_with_index do |(field_name, type), idx|
      if name == field_name
        return FieldExpr.new(base, idx, type)
      end
    end
    nil
  end
end

class UnionConstructor
  include GenSymbol
  attr_reader :name, :symbol, :conparams, :fields

  def initialize(symbol)
    @symbol = symbol

    w = symbol.new_walker
    w.take!(:union)
    @name = w.read_ident
    @conparams = read_conparams(w)
    @fields = read_fields(w)
    w.take!(:union_end)
  end

  def parse_args(constructed_type, args)
    if args.size != 1
      raise "union constructor only accepts on parameter"
    end

    name, value = *args.to_a[0]

    @fields.each_with_index do |(field_name, type), idx|
      if name == field_name
        resolved = ExprCompiler.resolve_type_recursive(type, constructed_type)
        if value.typeof != resolved
          raise "type error"
        end
        return [idx, value]
      end
    end

    raise "no such param: #{name}"
  end

  def construct(constructed_type, args)
    tag, value = parse_args(constructed_type, args)
    UnionLiteral.new(constructed_type, tag, value)
  end

  def field_expr(base, name, is_predicate:)
    @fields.each_with_index do |(field_name, type), idx|
      if name == field_name
        if is_predicate
          return UnionFieldPredicateExpr.new(base, idx)
        else
          return UnionFieldExpr.new(base, idx, type)
        end
      end
    end
    nil
  end
end

class TraitConstructor
  include GenSymbol
  attr_reader :name, :symbol, :conparams, :functions

  def initialize(symbol)
    @symbol = symbol

    w = symbol.new_walker
    w.take!(:trait)
    @name = w.read_ident
    @conparams = read_conparams(w)
    @functions = {}

    w.take!(:trait_body)

    while w.take(:func)
      decl = FunctionDecl.new(w, scope)
      @functions[decl.name] = decl
      w.take!(:func_end)
    end

    w.take!(:trait_end)
  end

  def backend
    @symbol.compiler.backend
  end

  def setup(type, name, scope)
    decl = @functions.fetch(name)
    impl_scope = scope.new_child(ImplementScope)
    impl_scope.type = type
    impl_scope.decl = decl
    syms = impl_scope.new_child
    impl = backend.new_function(decl.name, decl.params, decl.return_type)
    syms.target = impl.root_block
    return impl, syms
  end

  def field_expr(base, name, is_predicate: false)
    if decl = @functions[name]
      ObjectFieldExpr.new(base, decl)
    end
  end
end
