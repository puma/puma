require 'rubygems/package_task'
require 'hoe'

HOE = Hoe.spec 'mongrel' do
  self.rubyforge_name = 'mongrel'
  self.author         = ['Zed A. Shaw']
  self.email          = %w[mongrel-users@rubyforge.org]
  self.readme_file    = "README"
  self.need_tar       = false
  self.need_zip       = false

  spec_extras[:required_ruby_version] = Gem::Requirement.new('>= 1.8.6')

  spec_extras[:extensions] = ["ext/http11/extconf.rb"]
  spec_extras[:executables] = ['mongrel_rails']

  extra_deps << ['gem_plugin', '>= 0.2.3']
  extra_dev_deps << ['rake-compiler', ">= 0.5.0"]
end

file "#{HOE.spec.name}.gemspec" => ['Rakefile', 'tasks/gem.rake'] do |t|
  puts "Generating #{t.name}"
  File.open(t.name, 'w') { |f| f.puts HOE.spec.to_yaml }
end

desc "Generate or update the standalone gemspec file for the project"
task :gemspec => ["#{HOE.spec.name}.gemspec"]
