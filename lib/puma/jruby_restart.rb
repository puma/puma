require 'ffi'

module Puma
  module JRubyRestart
    extend FFI::Library
    ffi_lib 'c'

    attach_function :execlp, [:string, :varargs], :int
    attach_function :chdir, [:string], :int

    def self.chdir_exec(dir, cmd, *argv)
      chdir(dir)
      argv.unshift(cmd)
      argv = ([:string] * argv.size).zip(argv).flatten
      argv <<:int
      argv << 0
      execlp(cmd, *argv)
      raise SystemCallError.new(FFI.errno)
    end
  end
end

