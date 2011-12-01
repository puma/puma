module Puma
  class NullIO
    def gets
      nil
    end

    def each
    end

    def read(count)
      nil
    end

    def rewind
    end

    def close
    end
  end
end
