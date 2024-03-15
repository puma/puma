run lambda { |env|
  body = +"#{'─' * 70} Headers\n"
  env.sort.each { |k,v| body << "#{k.ljust 30} #{v}\n" }
  body << "#{'─' * 78}\n"
  [200, {"content-type" => "text/plain"}, [body]]
}
