class FilesController < ApplicationController
  session :off, :only => :progress
  
  def progress
    render :update do |page|
      @status = Mongrel::Uploads.check(params[:upload_id])
      page.upload_progress.update(@status[:size], @status[:received]) if @status
    end
  end
  
  def upload
    render :text => %(UPLOADED: #{params.inspect}.<script type="text/javascript">window.parent.UploadProgress.finish();</script>)
  end
end
