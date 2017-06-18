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
    when :array
      w.next
      exprs = []
      while !w.take(:array_end)
        exprs << compile(w, scope)
      end
      symbol = scope["Arr"]
      ArrayExpr.new(exprs, symbol.compile_expr)
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
      cases = []
      while true
        cond = compile(w, scope)
        branch = scope.new_child
        compile_block(w, branch)
        cases << [cond, branch]

        if w.take(:elseif)
          # continue
        elsif w.take(:else)
          branch = scope.new_child
          compile_block(w, branch)
          cases << [nil, branch]
          break
        else
          break
        end
      end
      BranchExpr.new(cases)
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
          type = expr.typeof
          expr = type.field(expr, name)
        else
          break
        end
      end

      expr
    when :return
      w.next
      expr = compile(w, scope)
      expected = scope.target.return_type

      if expr.respond_to?(:coerce_to)
        expr.coerce_to(expected)
      end

      if expr.typeof != expected
        raise "returned wrong type"
      end
      ReturnExpr.new(expr)
    else
      raise "Unknown tag: #{w.tag_name}"
    end
  end

  def matches?(value, target, free)
    if value == target
      return true
    end

    if value.is_a?(Function::CoercibleType)
      if value.type == target
        value.expr.coerce_to(target)
        return true
      end
    end

    if set = free[target]
      set << value
      return true
    end

    if target.is_a?(GencallExpr) && value.is_a?(GencallExpr)
      if target.struct != value.struct
        return false
      end

      value.mapping.each do |from, to|
        if !matches?(to, target.mapping[from], free)
          return false
        end
      end

      return true
    end

    return false
  end
end

