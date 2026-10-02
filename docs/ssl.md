# Configuring SSL / HTTPS with Puma

Two common setups:

1. **Terminate TLS at a reverse proxy** (nginx, Cloudflare, a load balancer) and speak plain HTTP or a Unix socket to Puma. Common when a proxy already handles certificates (for example Rails behind nginx in Docker).
2. **Terminate TLS in Puma** with `ssl://` binds or `ssl_bind`. Useful for local HTTPS, or when nothing sits in front of Puma.

If you are adding HTTPS in front of an app that already has a reverse proxy, start with [HTTPS with nginx in front of Puma](#https-with-nginx-in-front-of-puma). If you want Puma itself to speak TLS, see [HTTPS terminated by Puma](#https-terminated-by-puma).

## HTTPS with nginx in front of Puma

In this topology:

- Clients talk HTTPS to nginx.
- nginx holds the certificate and key.
- Puma binds a plain TCP port or Unix socket (no `ssl_bind`).
- nginx proxies to Puma and can set forwarding headers so the app knows the external request was HTTPS.

### Example `config/puma.rb` (no SSL on Puma)

```ruby
# Unix socket (when nginx shares the filesystem / volume with Puma):
bind 'unix:///myapp/tmp/puma.sock'

# Or TCP for container networking without a shared socket:
# bind 'tcp://0.0.0.0:9292'

threads 0, 5
```

Prefer `bundle exec puma` (or your process manager) so this config is used. Many bind options are unavailable via `rails server` — see the README Rails section.

### Example nginx HTTPS server

Minimal pattern: terminate TLS in nginx, proxy to Puma, set `X-Forwarded-Proto`:

```nginx
upstream myapp {
  server unix:///myapp/tmp/puma.sock;
  # Or: server puma:9292;
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

Also see [nginx.md](nginx.md) for a longer HTTP-oriented example.

Puma forwards `X-Forwarded-*` into the Rack env and uses them for some defaults (for example default server port). Your application or framework still needs to treat the request as HTTPS when appropriate. If the proxy does not set `X-Forwarded-Proto`, Puma's `rack_url_scheme 'https'` can set `env['rack.url_scheme']` — see [`Puma::DSL#rack_url_scheme`](../lib/puma/dsl.rb).

## HTTPS terminated by Puma

Use when clients connect to Puma directly over TLS.

### Why `ssl://` and not `https://`?

Bind URLs use a **socket scheme**, not an HTTP URL scheme. Accepted protocols are `tcp://`, `unix://`, and `ssl://`. `https://` is not a valid Puma bind.

### Why port `9292`?

`9292` is Puma's usual example port. Any free port works (Rails apps often use `3000`).

### CLI bind

```
$ puma -b 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert'
```

Using the sample certificates in this repository (from the repo root):

```
$ puma -b 'ssl://127.0.0.1:9292?key=examples/puma/puma_keypair.pem&cert=examples/puma/cert_puma.pem'
$ curl -k https://127.0.0.1:9292/
```

### Config file with `ssl_bind`

In `config/puma.rb` (or another file passed with `-C`):

```ruby
ssl_bind '127.0.0.1', '9292', {
  key: 'path_to_key',
  cert: 'path_to_cert',
  verify_mode: 'none' # default; ordinary server certificates
}
```

`ssl_bind` builds an `ssl://` URI. Full options: [`Puma::DSL#ssl_bind`](../lib/puma/dsl.rb).

### `verify_mode`

Default is `none` (do not verify client certificates) — appropriate for normal HTTPS server certs.

`peer` and `force_peer` are for **mutual TLS** (client certificates; typically with `ca`). They do not "turn on HTTPS." See [`Puma::DSL#ssl_bind`](../lib/puma/dsl.rb) and [`examples/puma/client_certs/`](../examples/puma/client_certs/).

### Self-signed certs in development

See the README section on the [`localhost`](https://github.com/socketry/localhost) gem.

## Example material in this repository

| Location | Contents |
| --- | --- |
| [`examples/puma/`](../examples/puma/) | Sample PEM/P12 material |
| [`examples/puma/client_certs/`](../examples/puma/client_certs/) | mTLS samples + runner |
| [`test/config/`](../test/config/) | Configs used by the test suite |
| [`lib/puma/dsl.rb`](../lib/puma/dsl.rb) | Authoritative `bind` / `ssl_bind` docs |

## Troubleshooting

### HTTPS client against a plain (non-SSL) bind

TLS to a `tcp://` or `unix://` bind fails with an HTTP parse error. One form is:

`Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?`

Depending on the ClientHello, you may see another malformed-request message instead. Use `http://` against a plain bind, or enable TLS with `ssl://` / `ssl_bind`.

### HTTP client against an SSL bind

Use `https://` (and trust or skip verification for self-signed certs).

### App behind a proxy still thinks requests are HTTP

Ensure the proxy sets `X-Forwarded-Proto https` (see [HTTPS with nginx in front of Puma](#https-with-nginx-in-front-of-puma)) and that your app/framework trusts that header. Or set `rack_url_scheme 'https'` in the Puma config when the proxy does not forward the scheme.
