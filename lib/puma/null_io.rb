module Puma

  # Provides an IO-like object that always appears to contain no data.
  # Used as the value for rack.input when the request has no body.
  #
  class NullIO

    # Always returns nil
    #
    def gets
      nil
    end

    # Never yields
    #
    def each
    end

    # Always returns nil
    #
    def read(count)
      nil
    end

    # Does nothing
    #
    def rewind
    end

    # Does nothing
    #
    def close
    end
  end
end
