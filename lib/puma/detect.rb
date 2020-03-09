# frozen_string_literal: true

module Puma
  IS_JRUBY = defined?(JRUBY_VERSION)

  def self.jruby?
    IS_JRUBY
  end

  IS_WINDOWS = RUBY_PLATFORM =~ /mswin|ming|cygwin/

  def self.windows?
    IS_WINDOWS
  end

  def self.mri?
    RUBY_ENGINE == 'ruby' || RUBY_ENGINE.nil?
  end
end
