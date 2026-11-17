# HTTPS with Puma

There are two common setups:

1. **TLS terminates at a reverse proxy** (nginx, a load balancer, a CDN). The proxy holds the certificate and talks plain HTTP to Puma over TCP or a Unix socket. Puma needs no SSL configuration.
2. **TLS terminates in Puma** with an `ssl://` bind or `ssl_bind`. Useful for local HTTPS, or when nothing sits in front of Puma.

## TLS at a reverse proxy

Bind Puma to a plain socket:

```ruby
# config/puma.rb
bind 'unix:///myapp/tmp/puma.sock'
# Or, when the proxy cannot share a filesystem with Puma (for example, separate containers):
# bind 'tcp://0.0.0.0:9292'
```

Terminate TLS in nginx and tell the app the original request was HTTPS:

```nginx
upstream myapp {
  server unix:///myapp/tmp/puma.sock;
}

server {
  listen 443 ssl;
  server_name myapp.com;

  ssl_certificate     /etc/nginx/certs/cert.pem;
  ssl_certificate_key /etc/nginx/certs/key.pem;

  location / {
    proxy_pass http://myapp;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }
}
```

Puma passes `X-Forwarded-Proto` through to the Rack env, and frameworks such as Rails use it to treat the request as HTTPS. If your proxy cannot set the header, `rack_url_scheme 'https'` in the Puma config sets `env['rack.url_scheme']` instead.

## TLS in Puma

From the command line:

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert'
```

Or in `config/puma.rb`:

```ruby
ssl_bind '127.0.0.1', '9292', {
  key: 'path_to_key',
  cert: 'path_to_cert'
}
```

Bind URLs name a socket type, not an HTTP scheme, so use `ssl://`. Puma accepts `tcp://`, `unix://`, and `ssl://`; `https://` is not a valid bind.

`verify_mode` controls client certificates, not whether HTTPS is on. The default, `none`, is right for an ordinary HTTPS server. `peer` and `force_peer` are for mutual TLS, usually together with `ca`.

See [`Puma::DSL#ssl_bind`](../lib/puma/dsl.rb) for every option, and [Binding TCP / Sockets and SSL](binding.md) for self-signed development certificates, cipher suites, and encrypted keys.
