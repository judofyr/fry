require_relative 'scope'
require_relative 'parse_utils'
require_relative 'function'
require_relative 'struct'
require_relative 'backend'

require 'pathname'

class FryFile
  attr_reader :scope, :path, :parse_result, :compiler, :included_files

  def initialize(path, compiler)
    @path = path
    @included_files = []
    @compiler = compiler

    @is_parsed = false

    @include_scope = IncludeScope.new(@compiler.root_scope)
    @include_scope.included_files = @included_files
    @scope = SymbolScope.new(@include_scope)
  end

  def dir
    @dir ||= Pathname.new(@path) + ".."
  end

  def new_walker(idx = 0)
    Parser::Walker.new(@parse_result, idx)
  end

  def parse
    return if @is_parsed

    input = Parser::Input.new(File.read(path))
    @parse_result = Parser::Fry.toplevels.parse(input)
    if !@parse_result.eos?
      raise "Parsing failed #{path}"
    end

    w = new_walker
    until w.done?
      tag = w.tag
      idx = w.idx

      case tag.name
      when :struct, :func
        w.next
        name = w.read_ident
        @scope[name] = FrySymbol.new(name, idx, self)
        end_name = :"#{tag.name}_end"
        w.next until w.tag_name == end_name
        w.next
      when :include
        w.next
        included_path = w.read_string
        full_path = dir + (included_path + ".fry")
        @included_files << @compiler.file(full_path.to_s)
      else
        raise "Unknown tag: #{tag.name}"
      end
    end

    @is_parsed = true
    self
  end
end

class FrySymbol
  attr_reader :name, :file

  def initialize(name, idx, file)
    @name = name
    @idx = idx
    @file = file
    @type = @file.parse_result.tags[@idx].name
  end

  def compiler
    @file.compiler
  end

  def new_walker
    @file.new_walker(@idx)
  end

  def compile_expr
    @expr ||= case @type
    when :func
      Function.new(self)
    when :struct
      FryStruct.new(self)
    else
      raise "Cannot compile #@type"
    end
  end
end

class Variable
  attr_accessor :symbol_name
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def assign_type(type)
    @type = type
  end

  def type
    @type or raise "Unknown type"
  end

  def compile_expr
    VariableExpr.new(self)
  end

  def symbol_name
    @symbol_name or raise "Unassigned variable"
  end
end

class Compiler
  attr_reader :root_scope, :backend
  attr_accessor :core_file

  def initialize
    @files = {}
    @file_queue = []
    @root_scope = SymbolScope.new
    @root_scope["Int32"] = Types.ints[32]
    @root_scope["Bool"] = Types.ints[32]
    @root_scope["Type"] = Types.any_trait
    @root_scope["NumType"] = Types.num_trait
    @root_scope["IntType"] = Types.int_trait
    @backend = JSBackend.new
  end

  def file(path)
    if @files.has_key?(path)
      @files[path]
    else
      file = FryFile.new(path, self)
      if core_file
        file.included_files << core_file
      end
      @file_queue << file
      @files[path] = file
    end
  end

  def process_files
    while file = @file_queue.pop
      file.parse
    end
  end
end

