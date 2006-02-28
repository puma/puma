
include Mongrel

class First < Plugin "/commands"
  def initialize(options = {})
    puts "First with options: #{options.inspect}"
  end
end

class Second < Plugin "/commands"
  def initialize(options = {})
    puts "Second with options: #{options.inspect}"
  end
end

class Last < Plugin "/commands"
  def initialize(options = {})
    puts "Last with options: #{options.inspect}"
  end
end

