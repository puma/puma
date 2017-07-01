require 'mkmf'

dir_config("puma_http11")

unless ENV["DISABLE_SSL"]
  dir_config("openssl")

  if %w'crypto libeay32'.find {|crypto| have_library(crypto, 'BIO_read')} and
      %w'ssl ssleay32'.find {|ssl| have_library(ssl, 'SSL_CTX_new')}

    have_header "openssl/bio.h"
  end
end

BROKEN_VERSIONS = %w(2.2.7 2.3.4 2.4.1)
if (BROKEN_VERSIONS.include? RUBY_VERSION)
  $defs << '-DBROKEN_RUBY'
  $defs << "-DVERSION_#{RUBY_VERSION.gsub('.', '_')}"
end

create_makefile("puma/puma_http11")
