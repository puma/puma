module Puma
  module Delegation
    def forward(what, who)
      module_eval <<-CODE
        def #{what}(*args, &blk)
          #{who}.#{what}(*args, &blk)
        end
      CODE
    end
  end
end
