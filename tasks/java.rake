if ENV['JAVA']

  require 'rake/javaextensiontask'

  # build http11 java extension
  Rake::JavaExtensionTask.new('puma_http11', HOE.spec) do |ext|
    ext.java_compiling do |gs|
      gs.dependencies.delete gs.dependencies.find { |d| d.name == 'daemons' }
    end
  end

end
