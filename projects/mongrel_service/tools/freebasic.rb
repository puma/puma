#--
# FreeBASIC project builder
# inspired by Asset Compiler by Jeremy Voorhis
# coded by Luis Lavena
#--

# FreeBASIC Project library for compilation.
# For example:
#
# namespace :projects do
#   project_task :my_fb_project do
#     lib         'static'
#     dylib       'dynamic library'
#     executable  'exename'
#     
#     build_to    'bin'
#     
#     define      'MY_DEFINE'
#     
#     main        'src/main.bas'
#     source      'src/other_module.bas'
#     source      "src/*.bas"
#   end
# end
#
# This example defines the following tasks:
#
#   rake projects:build                 # Build all projects
#   rake projects:clobber               # Clobber all projects
#   rake projects:my_fb_project:build   # Build the my_fb_project files
#   rake projects:my_fb_project:clobber # Remove the my_fb_project files
#   rake projects:my_fb_project:rebuild # Force a rebuild of the my_fb_project files
#   rake projects:rebuild               # Rebuild all projects

require 'rake/tasklib'
require 'pp'

module FreeBASIC
  # this help me reduce the attempts to remove already removed files.
  # works with src_files
  CLOBBER = Rake::FileList.new
  ON_WINDOWS = (RUBY_PLATFORM =~ /mswin|cygwin|bccwin/)
  
  class ProjectTask
    attr_accessor :name
    attr_accessor :output_name
    attr_accessor :type
    attr_accessor :build_path
    attr_accessor :defines
    attr_accessor :main_file
    attr_accessor :sources
    attr_accessor :libraries
    attr_accessor :search_path
    attr_accessor :libraries_path
    
    def initialize(name, &block)
      @name = name.to_s
      @build_path = '.'
      @defines = []
      @sources = Rake::FileList.new
      @libraries = []
      @search_path = []
      @libraries_path = []
      @options = {}
      
      instance_eval &block
      
      do_cleanup
      
      namespace @name do
        define_clobber_task
        define_rebuild_task
        define_build_directory_task
        define_build_task
      end
      add_dependencies_to_main_task
    end 
    
    public
      # using this will set your project type to :executable
      # and assign exe_name as the output_name for the project
      # it dynamically will assign extension when running on windows
      def executable(exe_name)
        @type = :executable
        @output_name = "#{exe_name}.#{(ON_WINDOWS ? "exe" : "")}"
        @real_file_name = @output_name
      end
      
      # lib will set type to :lib and assign 'lib#{lib_name}.a'
      # as output_name for the project
      def lib(lib_name)
        @type = :lib
        @output_name = lib_name
        @real_file_name = "lib#{lib_name}.a"
      end
      
      # dynlib will set type to :dynlib and assign '#{dll_name}.dll|so'
      # as output_name for this project
      def dylib(dll_name)
        @type = :dylib
        @output_name = "#{dll_name}.#{(ON_WINDOWS ? "dll" : "so")}"
        @real_file_name = @output_name
        @complement_file = "lib#{@output_name}.a"
      end
      
      # this set where the final, compiled executable should be linked
      # uses @build_path as variable
      def build_to(path)
        @build_path = path
      end
      
      # define allow you set compiler time options
      # collect them into @defines and use later
      # to call source file compilation process (it wil require cleanup)
      def define(*defines)
        @defines << defines
      end
      
      # main set @main_file to be the main module used during the linking
      # process. also, this module requires special -m flag during his
      # own compile process
      # question: in case @no main_file was set, will use the first 'source'
      # file defined as main? or it should raise a error?
      def main(main_file)
        @main_file = main_file
      end
      
      # used to collect sources files for compilation
      # it will take .bas, .rc, .res as sources
      # before compilation we should clean @sources!
      def source(*sources)
        @sources.include sources
      end
    
      # this is similar to sources, instead library linking is used
      # also will require cleanup services ;-)
      def library(*libraries)
        @libraries << libraries
      end
  
      # use this to set the include path when looking for, ehem, includes
      # (equals -i fbc compiler param)
      def search_path(*search_path)
        @search_path << search_path
      end 
      
      # use this to tell the compiler where to look for libraries
      # (equals -p fbc compiler param)
      def lib_path(*libraries_path)
        @libraries_path << libraries_path
      end
      
      # use this to add additional compiler parameters (like debug or errorchecking options)
      #
      def option(new_options = {})
        @options.merge!(new_options)
      end
      
    protected
      # this method will fix nested libraries and defines
      # also, if main_file is missing (or wasn't set) will shift the first one
      # as main
      def do_cleanup
        # remove duplicated definitions, flatten 
        @defines.flatten!
        @defines.uniq! if @defines.length > 1

        # set main_file
        if @type == :executable
          @main_file = @sources.shift unless defined?(@main_file)
        end
        
        # empty path? must be corrected
        @build_path = '.' if @build_path == ''
        
        # remove duplicates from sources
        @sources.uniq! if @sources.length > 1
        
        # now the libraries
        @libraries.flatten!
        @libraries.uniq! if @libraries.length > 1
        
        # search path
        @search_path.flatten!
        @search_path.uniq! if @search_path.length > 1
        
        # libraries path
        @libraries_path.flatten!
        @libraries_path.uniq! if @libraries_path.length > 1
        
        # if no target was set, default to executable
        unless defined?(@output_name)
          executable(@name)
        end
      end
      
      # return the compiled name version of the passed source file (src)
      # compiled_form("test.bas") => "test.o"
      def compiled_form(src)
        src.ext({ ".bas" => "o", ".rc" => "obj" }[File.extname(src)])
      end
      
      def compiled_project_file
        File.join @build_path, @real_file_name
      end
      
      def fbc_compile(source, target, main = nil)
        cmdline = []
        cmdline << "fbc"
        cmdline << "-g" if (@options.has_key?(:debug) && @options[:debug] == true)
        cmdline << "-#{@options[:errorchecking].to_s}" if @options.has_key?(:errorchecking)
        cmdline << "-profile" if (@options.has_key?(:profile) && @options[:profile] == true)
        cmdline << "-mt" if (@options.has_key?(:mt) && @options[:mt] == true)
        cmdline << "-c #{source}"
        cmdline << "-o #{target}"
        cmdline << "-m #{main}" unless main.nil?
        cmdline << @defines.collect { |defname| "-d #{defname}" }
        cmdline << @search_path.collect { |path| "-i #{path}" }
        cmdline.flatten.join(' ')
      end
      
      def fbc_link(target, files, extra_files = [])
        cmdline = []
        cmdline << "fbc"
        cmdline << "-g" if (@options.has_key?(:debug) && @options[:debug] == true)
        cmdline << "-profile" if (@options.has_key?(:profile) && @options[:profile] == true)
        cmdline << "-mt" if (@options.has_key?(:mt) && @options[:mt] == true)
        cmdline << "-#{@type.to_s}" unless @type == :executable
        cmdline << "-x #{target}"
        cmdline << files << extra_files
        cmdline << @defines.collect { |defname| "-d #{defname}" }
        unless @type == :lib
          cmdline << @libraries_path.collect { |path| "-p #{path}" }
          cmdline << @libraries.collect { |libname| "-l #{libname}" }
        end
        cmdline.flatten.join(' ')
      end
      
      def define_clobber_task
        desc "Remove all compiled files for #{@name}"
        task :clobber do
          # remove compiled and linked file
          rm compiled_project_file rescue nil #unless @type == :lib
          rm File.join(@build_path, @complement_file) rescue nil if @type == :dylib
          
          # remove main file
          rm compiled_form(@main_file) rescue nil
          
          # now the sources files
          # avoid attempt to remove the file two times (this is a bug in Rake)
          @sources.each do |src|
            # exclude compiled source files (c obj).
            unless src =~ /o$/
              target = compiled_form(src)
              unless CLOBBER.include?(target)
                CLOBBER.include(target)
                rm target rescue nil
              end
            end
          end
        end
      end
      
      def define_rebuild_task
        desc "Force a rebuild of files for #{@name}"
        task :rebuild => [:clobber, :build]
      end
      
      def define_build_directory_task
        directory @build_path
        task :build => @build_path
      end
      
      def define_build_task
        desc "Build project #{@name}"
        task :build
        
        # empty file task
        file compiled_project_file
        
        # compile main_file
        # use as pre-requisite the source filename
        if @type == :executable
          file compiled_form(@main_file) => @main_file do |t|
            # remove the path and the extension
            main_module = File.basename(t.name).ext
            sh fbc_compile(@main_file, t.name, main_module)
          end
        
          # add dependency
          file compiled_project_file => compiled_form(@main_file)
        end
        
        # gather files that are passed "as-is" to the compiler
        unprocessed_files = @sources.select { |rcfile| rcfile =~ /(res|rc|o|obj)$/ }
        
        @sources.each do |src|
          # is a unprocessed file?
          unless unprocessed_files.include?(src)
            target = compiled_form(src)
            
            # is already in our list of tasks?
            if not Rake::Task.task_defined?(target)
              # if not, compile
              
              file target => src do
                sh fbc_compile(src, target)
              end
            end
          
            # include dependency
            file compiled_project_file => target
          end
        end
        
        # now the linking process
        file compiled_project_file do |t|
          target = File.join(@build_path, @output_name)
          sh fbc_link(target, t.prerequisites, unprocessed_files)
        end
        
        # add the dependency
        task :build => compiled_project_file
      end

      # Adds dependencies in the parent namespace
      def add_dependencies_to_main_task
        desc 'Build all projects' unless task( :build ).comment
        task :build => "#{@name}:build"
        
        desc 'Clobber all projects' unless task( :clobber ).comment
        task :clobber => "#{@name}:clobber"
        
        desc 'Rebuild all projects' unless task( :rebuild ).comment
        task :rebuild => ["#{@name}:clobber", "#{@name}:build"]
      end
  end
end
  
# helper method to define a FreeBASIC::ProjectTask in the current namespace
def project_task name, &block
  FreeBASIC::ProjectTask.new name, &block
end

def include_projects_of name
  desc 'Build all projects' unless task( :build ).comment
  task :build => "#{name}:build"
  
  desc 'Clobber all projects' unless task( :clobber ).comment
  task :clobber => "#{name}:clobber"
  
  desc 'Rebuild all projects' unless task( :rebuild ).comment
  task :rebuild => "#{name}:rebuild"
end
