require 'hoe'

HOE = Hoe.spec 'puma' do
  self.rubyforge_name = 'puma'
  self.readme_file = "README.md"
  developer 'Evan Phoenix', 'evan@phx.io'

  spec_extras[:extensions] = ["ext/puma_http11/extconf.rb"]
  spec_extras[:executables] = ['puma']

  dependency 'rack', '~> 1.3'

  extra_dev_deps << ['rake-compiler', "~> 0.7.0"]

  clean_globs.push('test_*.log', 'log')
end

file "#{HOE.spec.name}.gemspec" => ['Rakefile', 'tasks/gem.rake'] do |t|
  puts "Generating #{t.name}"
  File.open(t.name, 'w') { |f| f.puts HOE.spec.to_ruby }
end

desc "Generate or update the standalone gemspec file for the project"
task :gemspec => ["#{HOE.spec.name}.gemspec"]
