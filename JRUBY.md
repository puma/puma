# JRuby

Puma supports JRuby and has a few additional _goodies_ depending on what is available on the classpath.

## Netty OpenSSL

For those interested in improving the performance of the SSLEngine; Puma has support to leverage Netty's
OpenSSL native bindings through [netty-tcnative](https://netty.io/wiki/forked-tomcat-native.html).

> Speed: In local testing, we've seen performance improvements of 3x over the JDK.
> GCM, which is used by the only cipher suite required by the HTTP/2 RFC, is 10-500x faster.

If all the requirments have been met (see below); you can enable Netty OpenSSL via the system property **puma.ssl.use-netty**

```
ENV_JAVA["puma.ssl.use-netty"] = true
or
-J-Dpuma.ssl.use-netty=true
```

Currently, Puma has been compiled against version **4.1.47.Final** of Netty; however it is likely that other
versions of Netty 4.X will function.

### Requirements

Requirements for the use of OpenSSL can be found [here](https://netty.io/wiki/requirements-for-4.x.html#tls-with-openssl)
however they boil down to:

1. OpenSSL version >= 1.0.2 for ALPN support, or version >= 1.0.1 for NPN.
2. netty-tcnative version >= 1.1.33.Fork7 must be on classpath.
3. Supported platforms: linux-x86_64, mac-x86_64, windows-x86_64. Supporting other platforms will require manually building netty-tcnative.

Reading the [documentation](https://netty.io/wiki/forked-tomcat-native.html) is a great way to make sure the requirements
are set.