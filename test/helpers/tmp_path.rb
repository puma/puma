module TmpPath
  def clean_tmp_paths
    while path = tmp_paths.pop
      delete_tmp_path(path)
    end
  end

  private

  # With some macOS configurations, the following error may be raised when
  # creating a UNIXSocket:
  #
  # too long unix socket path (106 bytes given but 104 bytes max) (ArgumentError)
  #
  PUMA_TMPDIR = RUBY_PLATFORM.include? 'darwin' ? './tmp' : nil

  def tmp_path(extension=nil)
    path = Tempfile.create(['', extension], PUMA_TMPDIR) { |f| f.path }
    tmp_paths << path
    path
  end

  def tmp_paths
    @tmp_paths ||= []
  end

  def delete_tmp_path(path)
    File.unlink(path)
  rescue Errno::ENOENT
  end
end
