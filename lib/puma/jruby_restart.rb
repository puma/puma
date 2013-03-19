require 'ffi'

module Puma
  module JRubyRestart
    extend FFI::Library
    ffi_lib 'c'

    attach_function :execlp, [:string, :varargs], :int
    attach_function :chdir, [:string], :int

    def self.chdir_exec(dir, argv)
      chdir(dir)
      cmd = argv.first
      argv = ([:string] * argv.size).zip(argv).flatten
      argv << :string
      argv << nil
      execlp(cmd, *argv)
      raise SystemCallError.new(FFI.errno)
    end
  end
end

