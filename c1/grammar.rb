require_relative 'parser'

module Parser
  Fry = Grammar.new do
    def ident(name = nil)
      if name
        # concrete ident
        str(name) >> char(:ident).not
      else
        # any type of ident
        char(:identfst) >> char(:ident).repeat >> tag(:ident_end)
      end
    end

    ## Various types of whitespace

    let(:space?) do
      char(:space).repeat
    end

    let(:space) do
      char(:space).many
    end

    # A comment (without the newline)
    let(:comment) do
      char(?#) >> (char(?\n).not >> any).repeat
    end

    # A newline (possibly preceeded by space/comment)
    let(:spaceline) do
      space? >> comment.maybe >> char(?\n)
    end

    ## Literals
    let(:string) do
      tag(:string) >> char(?") >>
      (
        (char(?\\) >> any) /
        (char(?").not >> any)
      ).repeat >>
      char(?") >> tag(:string_end)
    end

    let(:number) do
      tag(:number) >>
      (tag(:sign) >> char(?-)).maybe >>
      tag(:integer) >> char(:digit).many >>
      (char(?.) >> tag(:fractional) >> char(:digit).repeat).maybe >>
      tag(:number_end)
    end

    ## Toplevel statements

    let(:toplevel) do
      include_stmt / func / struct / union
    end

    let(:toplevels) do
      spaceline.repeat >>
      (toplevel >> spaceline.repeat).repeat
    end

    let(:include_stmt) do
      tag(:include) >> ident("include") >> space? >> string
    end

    let(:field) do
      space? >>
      tag(:field_name) >> ident >>
      char(?:) >> space? >> 
      tag(:field_type) >> expr >>
      spaceline
    end

    ## Function

    let(:func) do
      tag(:func) >>
      func_name >>
      field.repeat >>
      func_body >>
      tag(:func_end)
    end

    let(:func_name) do
      ident("function") >> space? >>
      tag(:func_name) >> ident >> spaceline
    end

    let(:func_body) do
      tag(:func_body) >> char(?{) >> block >> char(?})
    end

    ## Struct / Union

    let(:struct) do
      tag(:struct) >>
      ident("struct") >> type_block >>
      tag(:struct_end)
    end

    let(:union) do
      tag(:union) >>
      ident("union") >> type_block >>
      tag(:union_end)
    end

    let(:type_block) do
      space? >>
      type_name >>
      field.repeat >>
      type_body
    end

    let(:type_name) do
      tag(:type_name) >> ident >> spaceline
    end

    let(:type_body) do
      tag(:type_body) >>
      char(?{) >> spaceline >>
      field.repeat >>
      char(?})
    end

    ## Expressions

    let(:expr) do
      string / number / identexpr
    end

    let(:identexpr) do
      identcall >>
      (char(?.) >> tag(:field) >> identcall).repeat
    end

    let(:identcall) do
      tag(:ident) >> ident >> genargs.maybe >> call.maybe
    end

    let(:genargs) do
      tag(:genargs) >>
      char(?<) >>
      (tag(:arg) >> space? >> expr >> space?).join(char(?,)) >>
      char(?>) >>
      tag(:genargs_end) 
    end

    let(:call) do
      tag(:call) >>
      char(?() >>
      callparam.join(char(?,)).maybe >>
      char(?)) >>
      tag(:call_end)
    end

    let(:callparam) do
      tag(:arg_name) >> ident >>
      space? >> char(?=) >> space? >>
      expr >> space?
    end

    let(:assign) do
      space? >> char(?=) >> space? >>
      tag(:assign) >> expr
    end

    ## Statements

    let(:block) do
      spaceline.repeat >>
      (space? >> stmt >> spaceline.many).repeat >>
      space? >> tag(:block_end)
    end

    def stmt_block(name, inner = nil)
      if inner
        sinner = space? >> inner >> space?
      else
        sinner = space?
      end
      ident(name) >> sinner >> char(?{) >> block >> char(?})
    end

    let(:stmt) do
      if_stmt / while_stmt / var_stmt / return_stmt / assign_stmt
    end

    let(:if_stmt) do
      tag(:if) >>
      stmt_block("if", expr) >> 
      (space? >> stmt_block("else if", expr)).repeat >>
      (tag(:else) >> space? >> stmt_block("else")).maybe
    end

    let(:while_stmt) do
      stmt_block("while", expr)
    end

    let(:return_stmt) do
      tag(:return) >> ident("return") >> space? >> expr
    end

    let(:var_stmt) do
      ident("var") >> space? >>
      tag(:var) >> ident >> assign.maybe
    end

    let(:assign_stmt) do
      expr >> assign
    end
  end
end

