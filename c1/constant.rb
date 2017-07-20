class Constant
  attr_reader :value

  def initialize(value)
    @value = value
  end
end

class TypeConstant < Constant
end

class TypeConstructorConstant < Constant
end

class IntConstant < Constant
end

class ModuleConstant < Constant
end
