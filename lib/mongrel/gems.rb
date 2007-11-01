module Mongrel
  module Gems
    class << self
    
      alias :original_require :require
    
      def require(library, version = nil)
        begin
          original_require library
        rescue LoadError, RuntimeError => e
          unless respond_to? 'gem'
            # ActiveSupport breaks 'require' by making it always return a true value
            require 'rubygems'
            gem library, version if version
            retry 
          end
          # Fail without reraising
        end  
      end
      
    end    
  end
end