map "/worker_count" do
  run ->(env) {
    [200, {}, [Concurrent.available_processor_count.to_i.to_s]]
  }
end
