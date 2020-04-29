if %w(2.2.7 2.2.8 2.2.9 2.2.10 2.3.4 2.4.1).include? RUBY_VERSION
  begin
    require 'stopgap_13632'
  rescue LoadError
    STDERR.puts "WARNING: For stability, you should install the stopgap_13632 gem."
  end
end
