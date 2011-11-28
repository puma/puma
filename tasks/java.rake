if IS_JRUBY

  require 'rake/javaextensiontask'

  # build http11 java extension
  Rake::JavaExtensionTask.new('puma_http11', HOE.spec)

end
