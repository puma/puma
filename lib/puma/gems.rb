module Puma
  module Gems
    class << self
    
      def require(library, version = nil)
        begin
          Kernel.require library
        rescue LoadError, RuntimeError => e
          begin 
            # ActiveSupport breaks 'require' by making it always return a true value
            Kernel.require 'rubygems'
            version ? gem(library, version) : gem(library)
            retry
          rescue Gem::LoadError, LoadError, RuntimeError
            # puts "** #{library.inspect} could not be loaded" unless library == "puma_experimental"
          end
        end  
      end
      
    end    
  end
end
