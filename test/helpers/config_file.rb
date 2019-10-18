class TestConfigFileBase < Minitest::Test
  private

  def with_env(env = {})
    original_env = {}
    env.each do |k, v|
      original_env[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    original_env.each do |k, v|
      ENV[k] = v
    end
  end
end
