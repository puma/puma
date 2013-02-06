run lambda { |env|
  body = lambda { |io| io.puts "BLAH\n"; io.close }

  [200, { 'rack.hijack' => body }, []]
}
