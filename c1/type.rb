require_relative 'utils'

module Types
  module_function

  def void
    @void ||= VoidType.new
  end

  def ints
    @ints ||= Hash.new { |h, k| h[k] = IntType.new(k) }
  end

  def type
    @type ||= TypeType.new
  end
end

class Type
end

class VoidType < Type
end

class IntType < Type
  def initialize(bitsize)
    @bitsize = bitsize
  end
end

class TypeVariable < Type
  attr_reader :name
  def initialize(name)
    @name = name
  end
end

class TypeType < Type
end

class ConstructedType < Type
  attr_reader :constructor, :conargs

  include ValueEquality.new { [@constructor, @conargs] }

  def initialize(constructor, conargs)
    @constructor = constructor
    @conargs = conargs
  end

  def conparams
    @constructor.conparams
  end

  def resolve_type(type)
    if idx = conparams.index(type)
      return conargs[idx]
    end
    nil
  end
end

