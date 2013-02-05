module Puma
  module Util
    module_function

    def pipe
      IO.pipe
    end
  end
end
