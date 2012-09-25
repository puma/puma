module Process
  def self.daemon(nochdir=false, noclose=false)
    exit if fork                     # Parent exits, child continues.

    Process.setsid                   # Become session leader.

    exit if fork                     # Zap session leader. See [1].

    Dir.chdir "/" unless nochdir     # Release old working directory.

    if !noclose
      null = File.open "/dev/null"
      STDIN.reopen null
      STDOUT.reopen null
      STDERR.reopen null
    end

    0
  end unless respond_to?(:daemon)
end
