# use rake-compiler for building the extension
require 'rake/extensiontask'

# build http11 C extension
Rake::ExtensionTask.new('http11', HOE.spec) do |ext|
  # define target for extension (supporting fat binaries)
  if RUBY_PLATFORM =~ /mingw|mswin/ then
    RUBY_VERSION =~ /(\d+\.\d+)/
    ext.lib_dir = "lib/#{$1}"
  end

  # define cross-compilation tasks when not on Windows.
  unless RUBY_PLATFORM =~ /mingw|mswin/ then
    ext.cross_compile = true
    ext.cross_platform = ['i386-mswin32', 'i386-mingw32']

    ext.cross_compiling do |gs|
      gs.dependencies.delete gs.dependencies.find { |d| d.name == 'daemons' }
    end
  end
end

# ensure things are built prior testing
task :test => [:compile]
