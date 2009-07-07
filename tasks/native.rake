# use rake-compiler for building the extension
require 'rake/extensiontask'

# build http11 C extension
Rake::ExtensionTask.new('http11', HOE.spec) do |ext|
end

# ensure things are built prior testing
task :test => [:compile]
