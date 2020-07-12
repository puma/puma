module TmpPath
  def run(*args)
    begin
      result = super(*args)
    rescue Interrupt
      clean_tmp_paths
      raise
    end

    clean_tmp_paths
    result
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
    tmp_paths.each { |path| delete_tmp_path(path) }
    @tmp_paths = []
  end

  def delete_tmp_path(path)
    File.unlink(path)
  rescue Errno::ENOENT
  end
end
