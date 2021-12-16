module Puma
  module Signal
    module_function

    def prepend_handler(sig, &handler)
      name = signame(sig)
      custom_signal_handlers[signame] ||= []
      custom_signal_handlers[signame].prepend(handler)
    end

    # Signal.trap that does not replace
    # the existing puma handlers
    def trap(sig, &handler)
      name = signame(sig)
      ::Signal.trap(name) do
        invoke_custom_signal_handlers(name)
        yield handler
      end
    end

    private

    def signame(sig)
      name = sig.is_a?(Integer) ? ::Signal.signame(sig) : String(sig).sub('SIG', '')
      raise ArgumentError, "unsupported signal SIG#{name}" unless ::Signal.list[name]
      name
    end
    module_function :signame

    def invoke_custom_signal_handlers(signame)
      Array(custom_signal_handlers[signame]).each do |handler|
        yield handler
      end
    end
    module_function :invoke_custom_signal_handlers

    def custom_signal_handlers
      @custom_signal_handlers ||= {}
    end
    module_function :custom_signal_handlers
  end
end
