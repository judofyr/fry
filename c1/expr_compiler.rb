require_relative 'expr'

module ExprCompiler
  module_function

  def compile_block(w, scope)
    until w.tag_name == :block_end
      expr = compile(w, scope)
      expr.insert_into(scope.target)
    end
    w.next
  end

  def compile(w, scope)
    case w.tag_name
    when :number
      value = w.read_number
      IntExpr.new(value)
    when :void
      w.next
      VoidExpr.new
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
    when :while
      w.next
      cond = compile(w, scope)
      body = scope.new_child
      compile_block(w, body)
      WhileExpr.new(cond, body)
    when :ident
      name = w.read_ident
      symbol = scope[name]
      expr = symbol.compile_expr

      while true
        if w.take(:gencall)
          args = []
          while w.take(:arg)
            arg_expr = compile(w, scope)
            args << arg_expr.constant_value(TypeConstant)
          end
          w.take!(:gencall_end)
          if constructor = expr.constant_value(TypeConstructorConstant)
            type = ConstructedType.new(constructor, args)
            expr = TypeExpr.new(type)
          else
            raise "cannot instantiate"
          end
        end

        if w.take(:call)
          args = {}
          while w.tag_name == :arg_name
            arg_name = w.read_ident
            arg_expr = compile(w, scope)
            args[arg_name] = arg_expr
          end
          w.take!(:call_end)

          if type = expr.constant_value(TypeConstant)
            if type.is_a?(ConstructedType)
              expr = type.constructor.construct(type, args)
            else
              raise "cannot call"
            end
          elsif expr.is_a?(Function) or expr.is_a?(Constructor)
            # TODO: Replace with constant-function
            expr = expr.call(args)
          elsif expr.is_a?(ObjectFieldExpr)
            expr = expr.call(args)
          else
            raise "cannot call"
          end
        end

        if w.take(:field)
          name = w.read_ident
          is_predicate = w.take(:pred)
          type = expr.typeof
          if type.is_a?(ConstructedType)
            expr = type.constructor.field_expr(expr, name, is_predicate: is_predicate)
            raise "cannot find: #{name}" if expr.nil?
          elsif file = expr.constant_value(ModuleConstant)
            expr = file.scope.lookup(name).compile_expr
          else
            raise "cannot fetch field"
          end
        else
          break
        end
      end

      expr
    when :return
      w.next
      expr = compile(w, scope)
      expected = scope.target.return_type

      if expr.typeof != expected
        raise "returned wrong type"
      end
      ReturnExpr.new(expr)
    when :spawn
      w.next
      body = scope.new_child
      body.target.suspendable = true
      compile_block(w, body)
      SpawnExpr.new(body)
    when :try_block
      w.next
      body = scope.new_child
      body.target.throwable = true
      compile_block(w, body)
      w.take!(:else)
      handler = scope.new_child
      compile_block(w, handler)
      TryBlockExpr.new(body, handler)
    else
      raise "Unknown tag: #{w.tag_name}"
    end
  end

  def resolve_type_recursive(type, resolver)
    case type
    when TypeVariable
      if resolved = resolver.resolve_type(type)
        return resolved
      end
    when ConstructedType
      newargs = type.conargs.map do |arg|
        resolve_type_recursive(arg, resolver)
      end
      return ConstructedType.new(type.constructor, newargs)
    end
    type
  end
end

