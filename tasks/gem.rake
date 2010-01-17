require 'hoe'

HOE = Hoe.spec 'mongrel' do
  self.rubyforge_name = 'mongrel'
  developer 'Zed A. Shaw', 'mongrel-users@rubyforge.org'

  spec_extras[:required_ruby_version] = Gem::Requirement.new('>= 1.8.6')

  spec_extras[:extensions] = ["ext/http11/extconf.rb"]
  spec_extras[:executables] = ['mongrel_rails']

  extra_rdoc_files << 'LICENSE'

  extra_deps << ['gem_plugin', '~> 0.2.3']
  extra_deps << ['daemons', '~> 1.0.10']

  extra_dev_deps << ['rake-compiler', "~> 0.7.0"]

  clean_globs.push('test_*.log', 'log')
end

file "#{HOE.spec.name}.gemspec" => ['Rakefile', 'tasks/gem.rake'] do |t|
  puts "Generating #{t.name}"
  File.open(t.name, 'w') { |f| f.puts HOE.spec.to_yaml }
end

desc "Generate or update the standalone gemspec file for the project"
task :gemspec => ["#{HOE.spec.name}.gemspec"]
