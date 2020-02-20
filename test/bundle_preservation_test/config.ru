run(
  lambda do |env|
    [
      200,
      {'Content-Type'=>'text/plain'},
      [
        [ENV['BUNDLE_GEMFILE'], ENV['GEM_HOME']].inspect
      ]
    ]
  end
)
