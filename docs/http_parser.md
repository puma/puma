# HTTP Parser

Puma parses requests with `Puma::HttpParser`, which comes from its `puma_http11` extension, written in C for MRI and Java for JRuby. The `http_parser` option replaces it with another class.

```ruby
# config/puma.rb
require "puma/http1"
http_parser Puma::HTTP1::Parser
```

That example uses [puma-http1](https://github.com/veganstraightedge/puma-http1), a Ruby port of `Puma::HttpParser`. The class must be required before it is passed to `http_parser`. Puma does not search for parsers.

A parser gem shouldn’t define a constant directly under `Puma` with the same name as one in `Puma::Const`, such as `Puma::HTTP`. Puma’s code refers to those constants without the `Const::` prefix, and Ruby finds a constant defined directly under `Puma` first.

## Without the extension

Puma loads when `puma_http11` can’t be built or loaded. There is then no default parser, so a server raises a `LoadError` at startup unless `http_parser` is set. SSL is also unavailable, because `MiniSSL::Engine` lives in the same extension.

## The interface

Puma creates one parser per connection, with `new` and no arguments, and calls these methods on it:

| method                      | returns           | description                                                                                                                   |
| :-------------------------- | :---------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| `execute(env, data, start)` | `Integer`         | Parses the String `data` from byte offset `start`, fills the Hash `env`, and returns the total bytes of `data` parsed so far. |
| `finished?`                 | `true` or `false` | Whether the request line and headers are complete.                                                                            |
| `body`                      | `String`          | The bytes of `data` after the headers, once finished. This can include the start of a pipelined request.                      |
| `reset`                     | `nil`             | Clears all state, so the parser can read the next request on the same connection.                                             |

`Puma::HttpParser` also has `error?`, `nread`, and `finish`. Puma doesn’t call them, but a parser that matches `Puma::HttpParser` can be tested against it more easily.

### Partial requests

A request can arrive over several reads. Puma appends each read to the same buffer and calls `execute` again, passing the buffer and the value the previous call returned as `start`. The parser has to resume where it left off, including in the middle of a header line.

### Errors

For a request that isn’t valid HTTP, `execute` raises `Puma::HttpParserError`. Puma then responds with a 400 and closes the connection.

When the message includes `non-SSL`, Puma inspects the raw request and replaces the message with a more specific one, such as `Bad method` or `Bad headers`. `Puma::HttpParser` uses this message for any request that doesn’t follow the grammar:

```txt
Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?
```

`Puma::HttpParser` also raises when an element is longer than its limit:

| element      | limit in bytes |
| :----------- | -------------: |
| header name  |            256 |
| header value |          81920 |
| request URI  |          12288 |
| fragment     |           1024 |
| request path |           8192 |
| query string |          10240 |
| all headers  |         114688 |

## The env

`execute` fills these keys. Keys are Strings, and values are binary Strings with the bytes the client sent.

| key               | value                                                                                                       |
| :---------------- | :---------------------------------------------------------------------------------------------------------- |
| `REQUEST_METHOD`  | `GET`                                                                                                       |
| `REQUEST_URI`     | `/path?query`, without the fragment                                                                         |
| `REQUEST_PATH`    | `/path`. Not set for an absolute URI, such as `http://host/path`. Puma derives it from `REQUEST_URI` later. |
| `QUERY_STRING`    | `query`. Only set when there is a `?`, and not for an absolute URI.                                         |
| `FRAGMENT`        | the part after `#`. Only set when there is a `#`.                                                           |
| `SERVER_PROTOCOL` | `HTTP/1.1`                                                                                                  |

Each header becomes a key made from its name. Letters are uppercased, `-` becomes `_`, `_` becomes `,`, and the result gets an `HTTP_` prefix. So `X-Forwarded-For` becomes `HTTP_X_FORWARDED_FOR`.

The `_` to `,` mapping is a security measure. Without it, a client could send `X_Forwarded_For` to overwrite the value a proxy sets with `X-Forwarded-For`.

`Content-Length` and `Content-Type` become `CONTENT_LENGTH` and `CONTENT_TYPE`, without the prefix, following CGI.

Leading and trailing spaces and tabs are removed from header values. When a header appears more than once, its values are joined with `, `.
