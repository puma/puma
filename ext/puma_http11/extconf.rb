require 'mkmf'

dir_config("puma_http11")
if $mingw && RUBY_VERSION >= '2.4'
  append_cflags '-D_FORTIFY_SOURCE=2'
  append_ldflags '-fstack-protector'
  have_library 'ssp'
end

unless ENV["DISABLE_SSL"]
  dir_config("openssl")

  if %w'crypto libeay32'.find {|crypto| have_library(crypto, 'BIO_read')} and
      %w'ssl ssleay32'.find {|ssl| have_library(ssl, 'SSL_CTX_new')}

    have_header "openssl/bio.h"

    # below is  yes for 1.0.2 & later
    have_func  "DTLS_method"                  , "openssl/ssl.h"

    # below are yes for 1.1.0 & later, may need to check func rather than macro
    # with versions after 1.1.1
    have_func  "TLS_server_method"            , "openssl/ssl.h"
    have_macro "SSL_CTX_set_min_proto_version", "openssl/ssl.h"

    # Random.bytes available in Ruby 2.5 and later, Random::DEFAULT deprecated in 3.0
    if Random.respond_to?(:bytes)
      $defs.push("-DHAVE_RANDOM_BYTES")
      puts "checking for Random.bytes... yes"
    else
      puts "checking for Random.bytes... no"
    end
  end
end

create_makefile("puma/puma_http11")
