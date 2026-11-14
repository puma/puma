# Binding TCP / Sockets

Bind Puma to a socket with the `-b` (or `--bind`) flag:

```
$ puma -b tcp://127.0.0.1:9292
```

When using a TCP socket on Linux, Puma will automatically skip requests whose connection has closed by the time it's taken from the queue. If you'd like to avoid wasting time on connections that are closing after your app starts handling them, you can call `env["puma.connection_closed?"]` at any time during the lifecycle of a request. A `false` result does not guarantee that the connection will remain open. Puma cannot check this for you during a request: it is waiting for your app to return a response.

To use a UNIX Socket instead of TCP:

```
$ puma -b unix:///var/run/puma.sock
```

If you need to change the permissions of the UNIX socket, just add a umask parameter:

```
$ puma -b 'unix:///var/run/puma.sock?umask=0111'
```

Need a bit of security? Use SSL sockets:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert'
```
## Self-signed SSL certificates (via the [`localhost`] gem, for development use):

Puma supports the [`localhost`] gem for self-signed certificates. This is particularly useful if you want to use Puma with SSL locally, and self-signed certificates will work for your use-case. Currently, the integration can only be used in MRI.

Puma automatically configures SSL when the [`localhost`] gem is loaded in a `development` environment:

Add the gem to your Gemfile:
```ruby
group(:development) do
  gem 'localhost'
end
```

And require it implicitly using bundler:
```ruby
require "bundler"
Bundler.require(:default, ENV["RACK_ENV"].to_sym)
```

Alternatively, you can require the gem in your configuration file, either `config/puma/development.rb`, `config/puma.rb`, or set via the `-C` cli option:
```ruby
require 'localhost'
# configuration methods (from Puma::DSL) as needed
```

Additionally, Puma must be listening to an SSL socket:

```shell
$ puma -b 'ssl://localhost:9292' -C config/use_local_host.rb

# The following options allow you to reach Puma over HTTP as well:
$ puma -b ssl://localhost:9292 -b tcp://localhost:9393 -C config/use_local_host.rb
```

[`localhost`]: https://github.com/socketry/localhost

## Controlling SSL Cipher Suites

To use or avoid specific SSL ciphers for TLSv1.2 and below, use `ssl_cipher_filter` or `ssl_cipher_list` options.

### Ruby:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&ssl_cipher_filter=!aNULL:AES+SHA'
```

### JRuby:

```
$ puma -b 'ssl://127.0.0.1:9292?keystore=path_to_keystore&keystore-pass=keystore_password&ssl_cipher_list=TLS_RSA_WITH_AES_128_CBC_SHA,TLS_RSA_WITH_AES_256_CBC_SHA'
```

To configure the available TLSv1.3 ciphersuites, use `ssl_ciphersuites` option (not available for JRuby).

### Ruby:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&ssl_ciphersuites=TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256'
```

See https://www.openssl.org/docs/man1.1.1/man1/ciphers.html for cipher filter format and full list of cipher suites.

Disable TLS v1 with the `no_tlsv1` option:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&no_tlsv1=true'
```

## Controlling OpenSSL Verification Flags

To enable verification flags offered by OpenSSL, use `verification_flags` (not available for JRuby):

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&verification_flags=PARTIAL_CHAIN'
```

You can also set multiple verification flags (by separating them with a comma):

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&verification_flags=PARTIAL_CHAIN,CRL_CHECK'
```

List of available flags: `USE_CHECK_TIME`, `CRL_CHECK`, `CRL_CHECK_ALL`, `IGNORE_CRITICAL`, `X509_STRICT`, `ALLOW_PROXY_CERTS`, `POLICY_CHECK`, `EXPLICIT_POLICY`, `INHIBIT_ANY`, `INHIBIT_MAP`, `NOTIFY_POLICY`, `EXTENDED_CRL_SUPPORT`, `USE_DELTAS`, `CHECK_SS_SIGNATURE`, `TRUSTED_FIRST`, `SUITEB_128_LOS_ONLY`, `SUITEB_192_LOS`, `SUITEB_128_LOS`, `PARTIAL_CHAIN`, `NO_ALT_CHAINS`, `NO_CHECK_TIME`
(see https://www.openssl.org/docs/manmaster/man3/X509_VERIFY_PARAM_set_hostflags.html#VERIFICATION-FLAGS).

## Controlling OpenSSL Password Decryption

To enable runtime decryption of an encrypted SSL key (not available for JRuby), use `key_password_command`:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert&key_password_command=/path/to/command.sh'
```

`key_password_command` must:

1. Be executable by Puma.
2. Print the decryption password to stdout.

 For example:

```shell
#!/bin/sh

echo "this is my password"
```

`key_password_command` can be used with `key` or `key_pem`. If the key
is not encrypted, the executable will not be called.
