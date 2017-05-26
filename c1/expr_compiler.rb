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

      while true
        if w.take(:gencall)
          args = []
          while w.take(:arg)
            args << compile(w, scope)
          end
          w.take!(:gencall_end)
          expr = expr.gencall(args)
        end

        if w.take(:call)
          args = {}
          while w.tag_name == :arg_name
            arg_name = w.read_ident
            value = compile(w, scope)
            args[arg_name] = value
          end
          w.take!(:call_end)
          expr = expr.call(args)
        end

        if w.take(:field)
          name = w.read_ident
          case type = expr.typeof
          when StructType
            expr = type.field(expr, name)
          else
            raise "no such field: #{name}"
          end
        else
          break
        end
      end

      expr
    else
      raise "Unknown tag: #{w.tag_name}"
    end
  end

  def typecheck(expr, type, mapping)
    if expr.typeof == type
      return true
    end

    if type.is_a?(Genparam)
      if mapped_type = mapping[type]
        return mapped_type == expr.typeof
      else
        raise "this should never happen?"
        mapping[type] = expr.typeof
        return true
      end
    end

    if type.is_a?(VariableExpr)
      param = type.variable
      # TODO: maybe subclass fn-params
      if mapped_type = mapping[param]
        return mapped_type == expr.typeof
      else
        mapping[param] = expr.typeof
        return true
      end
    end

    return false
  end
end

