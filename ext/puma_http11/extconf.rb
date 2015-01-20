require 'mkmf'

dir_config("puma_http11")

if %w'crypto libeay32'.find {|crypto| have_library(crypto, 'BIO_read')} and
    %w'ssl ssleay32'.find {|ssl| have_library(ssl, 'SSL_CTX_new')}
  
  create_makefile("puma/puma_http11")
end
