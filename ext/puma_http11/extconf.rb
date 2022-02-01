require 'mkmf'

dir_config("puma_http11")

if $mingw && RUBY_VERSION >= '2.4'
  append_cflags  '-fstack-protector-strong -D_FORTIFY_SOURCE=2'
  append_ldflags '-fstack-protector-strong -l:libssp.a'
  have_library 'ssp'
end

unless ENV["DISABLE_SSL"]
  dir_config("openssl")

  found_ssl = if (!$mingw || RUBY_VERSION >= '2.4') && (t = pkg_config 'openssl')
    puts 'using OpenSSL pkgconfig (openssl.pc)'
    true
  elsif %w'crypto libeay32'.find {|crypto| have_library(crypto, 'BIO_read')} &&
      %w'ssl ssleay32'.find {|ssl| have_library(ssl, 'SSL_CTX_new')}
    true
  else
    puts '** Puma will be compiled without SSL support'
    false
  end

  if found_ssl
    have_header "openssl/bio.h"

    # below is  yes for 1.0.2 & later
    have_func  "DTLS_method"                           , "openssl/ssl.h"

    # below are yes for 1.1.0 & later
    have_func  "TLS_server_method"                     , "openssl/ssl.h"
    have_func  "SSL_CTX_set_min_proto_version(NULL, 0)", "openssl/ssl.h"

    have_func  "X509_STORE_up_ref"
    have_func "SSL_CTX_set_ecdh_auto(NULL, 0)"         , "openssl/ssl.h"

    # below are yes for 3.0.0 & later, use for OpenSSL 3 detection
    have_func "SSL_get1_peer_certificate"              , "openssl/ssl.h"

    # Random.bytes available in Ruby 2.5 and later, Random::DEFAULT deprecated in 3.0
    if Random.respond_to?(:bytes)
      $defs.push "-DHAVE_RANDOM_BYTES"
      puts "checking for Random.bytes... yes"
    else
      puts "checking for Random.bytes... no"
    end
  end
end

if ENV["MAKE_WARNINGS_INTO_ERRORS"]
  # Make all warnings into errors
  # Except `implicit-fallthrough` since most failures comes from ragel state machine generated code
  if respond_to?(:append_cflags, true) # Ruby 2.5 and later
    append_cflags(config_string('WERRORFLAG') || '-Werror')
    append_cflags '-Wno-implicit-fallthrough'
  else
    # flag may not exist on some platforms, -Werror may not be defined on some platforms, but
    # works with all in current CI
    $CFLAGS << " #{config_string('WERRORFLAG') || '-Werror'}"
    $CFLAGS << ' -Wno-implicit-fallthrough'
  end
end

create_makefile("puma/puma_http11")
