require_relative 'expr'

module ExprCompiler
  module_function

  def compile_block(w, scope)
    until w.tag_name == :block_end
      expr = compile(w, scope)
      scope.target << expr
    end
    w.next
  end

  def compile(w, scope)
    case w.tag_name
    when :number
      num = w.read_number
      IntegerExpr.new(num)
    when :var
      varname = w.read_ident
      var = Variable.new(varname)
      scope.target.register_variable(var)

      if w.take(:assign)
        value = compile(w, scope)
        var.assign_type(value.typeof)
        expr = AssignExpr.new(var, value)
      end
      scope[varname] = var
      expr
    when :if
      w.next
      cond = compile(w, scope)
      tbranch = scope.new_child
      compile_block(w, tbranch)
      BranchExpr.new(cond, tbranch)
    when :ident
      name = w.read_ident
      symbol = scope[name]
      expr = symbol.compile_expr

      if w.take(:call)
        args = {}
        while w.tag_name == :arg_name
          arg_name = w.read_ident
          value = compile(w, scope)
          args[arg_name] = value
        end
        expr = expr.call(args)
      end
      expr
    else
      raise "Unknown tag: #{w.tag_name}"
    end
  end
end

