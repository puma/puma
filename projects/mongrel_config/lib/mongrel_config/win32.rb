require 'win32/service'


# Simply abstracts the common stuff that the config tool needs to do
# when dealing with Win32.  It is a very thin wrapper which may expand
# later.
module W32Support

  # Lists all of the services that have "mongrel" in the binary_path_name
  # of the service.  This detects the mongrel services.
  def W32Support.list
    Win32::Service.services.select {|s| s.binary_path_name =~ /mongrel/ }
  end

  # Just gets the display name of the service.
  def W32Support.display(name)
    Win32::Service.getdisplayname(name)
  end

  # Performs one operations (like :start or :start) which need
  # to be "monitored" until they're done.  The wait_for parameter
  # should be a regex for the content of the status like /running/
  # or /stopped/
  def W32Support.do_and_wait(service_name, operation, wait_for)
    status = W32Support.status(service_name)
    if status =~ wait_for
      # already running call the block once and leave
      yield status
    else
      # start trying to start it
      Win32::Service.send(operation, service_name)
      status = W32Support.status(service_name)
      while status !~ wait_for
        yield status
        status = W32Support.status(service_name)
      end

      # do one last yield so they know it started
      yield status
    end
  end

  # Starts the requested service and calls a passed in block
  # until the service is done.  You should sleep for a short
  # period until it's done or there's an exception.
  def W32Support.start(service_name)
    W32Support.do_and_wait(service_name, :start, /running/) do |status|
      yield status
    end
  end


  # Stops the service.  Just like W32Support.start is will call
  # a block while it checks for the service to actually stop.
  def W32Support.stop(service_name)
    W32Support.do_and_wait(service_name, :stop, /stopped/) do |status|
      yield status
    end
  end


  # Returns the current_state field of the service.
  def W32Support.status(service_name)
    Win32::Service.status(service_name).current_state
  end 
   

  # Deletes the service from the system.  It first tries to stop
  # the service, and if you pass in a block it will call it while
  # the service is being stopped.
  def W32Support.delete(service_name)
    begin
      W32Support.stop(service_name) do |status|
        yield status if block_given?
      end
    rescue
    end

    begin 
      Win32::Service.delete(service_name)
    rescue
    end
  end

end
