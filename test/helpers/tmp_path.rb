module TmpPath
  def clean_tmp_paths
    while path = tmp_paths.pop
      delete_tmp_path(path)
    end
  end

  private

  def tmp_path(extension=nil)
    path = Tempfile.create(['', extension]) { |f| f.path }
    tmp_paths << path
    path
  end

  def tmp_path_write(basename, data, mode: File::BINARY)
    fio = Tempfile.create basename, mode: mode
    path = fio.path
    fio.write data
    fio.flush
    fio.close
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
