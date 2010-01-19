require 'rake/javaextensiontask'

# build http11 java extension
Rake::JavaExtensionTask.new('http11_java', HOE.spec) do |ext|
end
