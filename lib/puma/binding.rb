module Puma
  class Binding
    include Puma::Const
    extend Forwardable

    def initialize(uri)
      @server = nil
    end

    attr_reader :server

    def to_s
      raise NotImplementedError
    end

    def env
      raise NotImplementedError
    end

    def_delegators :@server, :close, :local_address, :no_tlsv1, :no_tlsv1_1
  end
end
