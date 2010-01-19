require 'rake/javaextensiontask'

# build http11 java extension
Rake::JavaExtensionTask.new('http11', HOE.spec) do |ext|
end
