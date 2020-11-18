# Compile Options

There provide some `cflags` to change Puma's default configuration for C.

## Query String

By default, the max length of `QUERY_STRING` is `1024 * 10`. But you may want to adjust it to allow accept large queries in the GET requests.

For manual install

```
gem install puma -- --with-cflags="-D PUMA_QUERY_STRING_MAX_LENGTH=64000"
```

For bundler config

```
bundle config build.puma --with-cflags="-D PUMA_QUERY_STRING_MAX_LENGTH=64000"
```
