module Puma
  IS_JRUBY = defined?(JRUBY_VERSION)

  def self.jruby?
    IS_JRUBY
  end

  def self.windows?
    RUBY_PLATFORM =~ /mswin32|ming32/
  end
end
