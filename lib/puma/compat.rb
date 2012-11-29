# Provides code to work properly on 1.8 and 1.9

class String
  unless method_defined? :bytesize
    alias_method :bytesize, :size
  end

  unless method_defined? :byteslice
    alias_method :byteslice, :[]
  end
end
