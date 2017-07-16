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
      when :struct, :union, :func, :trait
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

  def static?
    true
  end

  def constructor
    @constructor ||= case @type
    when :struct
      StructConstructor.new(self)
    when :union
      UnionConstructor.new(self)
    when :trait
      TraitConstructor.new(self)
    end
  end

  def compile_expr
    @expr ||= case @type
    when :func
      Function.new(self)
    when :struct, :union, :trait
      if constructor.conparams.empty?
        TypeExpr.new(ConstructedType.new(constructor, []))
      else
        TypeConstructorExpr.new(constructor)
      end
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
    if !type.is_a?(Type)
      raise "not a type: #{type}"
    end
    @type = type
  end

  def type
    @type or raise "Unknown type"
  end

  def compile_expr
    LoadExpr.new(self)
  end

  def static?
    false
  end

  def to_js
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
    @root_scope["Int32"] = TypeExpr.new(Types.ints[32])
    @root_scope["Bool"] = TypeExpr.new(Types.ints[32])
    @root_scope["Type"] = TypeExpr.new(Types.type)
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

