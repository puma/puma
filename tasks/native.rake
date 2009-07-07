# use rake-compiler for building the extension
require 'rake/extensiontask'

# build http11 C extension
Rake::ExtensionTask.new('http11', HOE.spec) do |ext|
  # define target for extension (supporting fat binaries)
  if RUBY_PLATFORM =~ /mingw/ then
    RUBY_VERSION =~ /(\d+\.\d+)/
    ext.lib_dir = "lib/#{$1}"
  end
end

# ensure things are built prior testing
task :test => [:compile]
