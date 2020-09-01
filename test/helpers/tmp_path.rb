module TmpPath
  def capture_exceptions
    super
  rescue
    clean_tmp_paths
    raise
  ensure
    clean_tmp_paths
  end

  private

  def tmp_path(extension=nil)
    sock_file = Tempfile.new(['', extension])
    path = sock_file.path
    sock_file.close!
    tmp_paths << path
    path
  end

  def tmp_paths
    @tmp_paths ||= []
  end

  def clean_tmp_paths
    while path = tmp_paths.pop
      delete_tmp_path(path)
    end
  end

  def delete_tmp_path(path)
    File.unlink(path)
  rescue Errno::ENOENT
  end
end
