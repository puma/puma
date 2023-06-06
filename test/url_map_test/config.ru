map "/ok" do
  run ->(env) {
    if Object.const_defined?(:Rack) && ::Rack.const_defined?(:URLMap)
      [200, {}, ["::Rack::URLMap is loaded"]]
    else
      [200, {}, ["OK"]]
    end
  }
end
