
class First < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "First with options: #{options.inspect}"
  end
end

class Second < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "Second with options: #{options.inspect}"
  end
end

class Last < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "Last with options: #{options.inspect}"
  end
end

