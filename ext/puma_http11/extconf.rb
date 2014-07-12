require 'mkmf'

dir_config("puma_http11")

$defs.push "-Wno-deprecated-declarations"

if %w'ssl ssleay'.find {|ssl| have_library(ssl, 'SSL_CTX_new')} and
  %w'crypto libeay'.find {|crypto| have_library(ssl, 'BIO_read')}

  create_makefile("puma/puma_http11")
end
