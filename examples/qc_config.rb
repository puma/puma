  full_hostname = `hostname`.strip
  domainname = full_hostname.split('.')[1..-1].join('.')
  hostname = full_hostname.split('.')[0]

  CA[:hostname] = hostname
  CA[:domainname] = domainname
  CA[:CA_dir] = File.join Dir.pwd, "CA"
  CA[:password] = 'puma'
  
  CERTS << {
    :type => 'server',
    :hostname => 'puma'
  }
