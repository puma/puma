begin
  require 'rack'

  if Gem::Version.new(Rack.release) >= Gem::Version.new("3.0.0")
    raise StandardError.new "Puma 5 is not compatible with Rack 3, please upgrade to Puma 6 or higher."
  end
rescue LoadError
end
