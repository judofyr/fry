require_relative 'expr'

class Genparam < Expr
  attr_reader :name, :type

  def initialize(name, type)
    @name = name
    @type = type
  end

  def compile_expr
    self
  end
end

class FryStruct < Expr
  attr_reader :genparams, :fields

  def initialize(symbol)
    @symbol = symbol
    @types = {}

    file_scope = symbol.file.scope
    @scope = SymbolScope.new(file_scope)

    w = symbol.new_walker
    w.take!(:struct)

    @name = w.read_ident

    @genparams = []
    while w.tag_name == :field_name
      param_name = w.read_ident
      w.take!(:field_type)
      type = ExprCompiler.compile(w, file_scope)
      genparam = Genparam.new(param_name, type)
      @genparams << genparam
      @scope[param_name] = genparam
    end

    w.take!(:type_body)
    @fields = []
    while w.tag_name == :field_name
      param_name = w.read_ident
      w.take!(:field_type)
      type = ExprCompiler.compile(w, @scope)
      @fields << [param_name, type]
    end

    w.take!(:struct_end)
  end

  def generic?
    @genparams.any?
  end

  def gencall(arglist)
    # TODO: typecheck args
    mapping = {}
    @genparams.zip(arglist) do |param, arg|
      mapping[param] = arg
    end
    GenericExpr.new(self, mapping)
  end

  def call(args)
    # TODO: error on extra arguments
    values = @fields.map { |name, type| args.fetch(name) }
    StructLiteral.new(self, values)
  end

  def field(expr, name)
    @fields.each_with_index do |(field_name, type), idx|
      if name == field_name
        return FieldExpr.new(expr, idx, type)
      end
    end
    raise "no such field: #{name}"
  end
end

