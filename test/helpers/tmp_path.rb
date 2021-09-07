module TmpPath
  def clean_tmp_paths
    while path = tmp_paths.pop
      delete_tmp_path(path)
    end
  end

  private

  def tmp_path(extension=nil, contents: nil)
    if contents
      f = Tempfile.create(['', extension])
      f.write "#{contents.strip}\n"
      path = f.path
      f.close
    else
      path = Tempfile.create(['', extension]) { |fh| fh.path }
    end
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
