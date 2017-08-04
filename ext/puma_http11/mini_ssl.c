#define RSTRING_NOT_MODIFIED 1

#include <ruby.h>
#include <ruby/version.h>

#if RUBY_API_VERSION_MAJOR == 1
#include <rubyio.h>
#else
#include <ruby/io.h>
#endif

#ifdef HAVE_OPENSSL_BIO_H

#include <openssl/bio.h>
#include <openssl/ssl.h>
#include <openssl/dh.h>
#include <openssl/err.h>
#include <openssl/x509.h>

#ifndef SSL_OP_NO_COMPRESSION
#define SSL_OP_NO_COMPRESSION 0
#endif

typedef struct {
  unsigned char* buf;
  int bytes;
} ms_cert_buf;

typedef struct {
  BIO* read;
  BIO* write;
  SSL* ssl;
  SSL_CTX* ctx;
  VALUE rb_mini_ssl_ctx;
  ms_cert_buf* failed_cert;
} ms_conn;


void engine_free(ms_conn* conn) {
  if (conn->failed_cert) {
    OPENSSL_free(conn->failed_cert->buf);
    free(conn->failed_cert);
  }
  SSL_free(conn->ssl);
  SSL_CTX_free(conn->ctx);

  free(conn);
}

ms_conn* engine_alloc(VALUE klass, VALUE* obj) {
  ms_conn* conn;

  *obj = Data_Make_Struct(klass, ms_conn, 0, engine_free, conn);

  conn->read = BIO_new(BIO_s_mem());
  BIO_set_nbio(conn->read, 1);

  conn->write = BIO_new(BIO_s_mem());
  BIO_set_nbio(conn->write, 1);

  conn->ssl = 0;
  conn->ctx = 0;
  conn->rb_mini_ssl_ctx = Qnil;
  conn->failed_cert = 0;

  return conn;
}

DH *get_dh1024() {
  /* `openssl dhparam 1024 -C`
   * -----BEGIN DH PARAMETERS-----
   * MIGHAoGBALPwcEv0OstmQCZdfHw0N5r+07lmXMxkpQacy1blwj0LUqC+Divp6pBk
   * usTJ9W2/dOYr1X7zi6yXNLp4oLzc/31PUL3D9q8CpGS7vPz5gijKSw9BwCTT5z9+
   * KF9v46qw8XqT5HHV87sWFlGQcVFq+pEkA2kPikkKZ/X/CCcpCAV7AgEC
   * -----END DH PARAMETERS-----
   */
  static unsigned char dh1024_p[] = {
    0xB3,0xF0,0x70,0x4B,0xF4,0x3A,0xCB,0x66,0x40,0x26,0x5D,0x7C,
    0x7C,0x34,0x37,0x9A,0xFE,0xD3,0xB9,0x66,0x5C,0xCC,0x64,0xA5,
    0x06,0x9C,0xCB,0x56,0xE5,0xC2,0x3D,0x0B,0x52,0xA0,0xBE,0x0E,
    0x2B,0xE9,0xEA,0x90,0x64,0xBA,0xC4,0xC9,0xF5,0x6D,0xBF,0x74,
    0xE6,0x2B,0xD5,0x7E,0xF3,0x8B,0xAC,0x97,0x34,0xBA,0x78,0xA0,
    0xBC,0xDC,0xFF,0x7D,0x4F,0x50,0xBD,0xC3,0xF6,0xAF,0x02,0xA4,
    0x64,0xBB,0xBC,0xFC,0xF9,0x82,0x28,0xCA,0x4B,0x0F,0x41,0xC0,
    0x24,0xD3,0xE7,0x3F,0x7E,0x28,0x5F,0x6F,0xE3,0xAA,0xB0,0xF1,
    0x7A,0x93,0xE4,0x71,0xD5,0xF3,0xBB,0x16,0x16,0x51,0x90,0x71,
    0x51,0x6A,0xFA,0x91,0x24,0x03,0x69,0x0F,0x8A,0x49,0x0A,0x67,
    0xF5,0xFF,0x08,0x27,0x29,0x08,0x05,0x7B
  };
  static unsigned char dh1024_g[] = { 0x02 };

  DH *dh;
  dh = DH_new();

#if OPENSSL_VERSION_NUMBER < 0x10100005L || defined(LIBRESSL_VERSION_NUMBER)
  dh->p = BN_bin2bn(dh1024_p, sizeof(dh1024_p), NULL);
  dh->g = BN_bin2bn(dh1024_g, sizeof(dh1024_g), NULL);

  if ((dh->p == NULL) || (dh->g == NULL)) {
    DH_free(dh);
    return NULL;
  }
#else
  BIGNUM *p, *g;
  p = BN_bin2bn(dh1024_p, sizeof(dh1024_p), NULL);
  g = BN_bin2bn(dh1024_g, sizeof(dh1024_g), NULL);

  if (p == NULL || g == NULL || !DH_set0_pqg(dh, p, NULL, g)) {
    DH_free(dh);
    BN_free(p);
    BN_free(g);
    return NULL;
  }
#endif

  return dh;
}

/* retrieves the ms_conn* and copies the failed cert.  Returns 0, a value
 * suitable for returning from the verify callback.  if x509_error is not -1,
 * that error state is set on the context.
 */
static int engine_verify_failed(X509_STORE_CTX* ctx, int x509_error)
{
  SSL* ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
  ms_conn* conn = SSL_get_app_data(ssl);
  X509* cert = X509_STORE_CTX_get_current_cert(ctx);

  if (x509_error != -1) {
    X509_STORE_CTX_set_error(ctx, x509_error);
  }

  if (cert) {
    unsigned char* buf = NULL;
    int bytes = i2d_X509(cert, &buf);
    if (bytes > 0) {
      conn->failed_cert = (ms_cert_buf*) malloc(sizeof(ms_cert_buf));
      conn->failed_cert->buf = buf;
      conn->failed_cert->bytes = bytes;
    }
  }

  return 0;
}

static int engine_verify_callback(int preverify_ok, X509_STORE_CTX* ctx) {
  int depth = X509_STORE_CTX_get_error_depth(ctx);
  X509* cert = X509_STORE_CTX_get_current_cert(ctx);
  SSL* ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
  ms_conn* conn = SSL_get_app_data(ssl);

  ID sym_verify_name = rb_intern("verify_name");
  VALUE verify_name = rb_funcall(conn->rb_mini_ssl_ctx, sym_verify_name, 0);

  if (!preverify_ok || !cert || !ssl || !conn) {
    return engine_verify_failed(ctx, -1);
  }

  /* We only want to do explicit name validation on the leaf cert.  It allows
   * more opportunities to fail, but none to succeed.
   */
  if (depth == 0 && !NIL_P(verify_name)) {
    /* To keep this simple, we're explicitly only checking the first
     * commonName, and not walking subjectAlternateNames
     */
    char cname_buf[256];
    int entry;
    VALUE peer_common_name;

    X509_NAME* subject_name = X509_get_subject_name(cert);

    if (! subject_name) {
      return engine_verify_failed(ctx, X509_V_ERR_APPLICATION_VERIFICATION);
    }

    entry = X509_NAME_get_text_by_NID(subject_name, NID_commonName,
                                      cname_buf, sizeof(cname_buf));
    if (entry == -1) {
      return engine_verify_failed(ctx, X509_V_ERR_APPLICATION_VERIFICATION);
    }

    peer_common_name = rb_str_new_cstr(cname_buf);
    if (! rb_equal(verify_name, peer_common_name)) {
      return engine_verify_failed(ctx, X509_V_ERR_APPLICATION_VERIFICATION);
    }
  }

  return preverify_ok;
}

VALUE engine_init_server(VALUE self, VALUE mini_ssl_ctx) {
  VALUE obj;
  SSL_CTX* ctx;
  SSL* ssl;

  ms_conn* conn = engine_alloc(self, &obj);
  conn->rb_mini_ssl_ctx = mini_ssl_ctx;

  ID sym_key = rb_intern("key");
  VALUE key = rb_funcall(mini_ssl_ctx, sym_key, 0);

  StringValue(key);

  ID sym_cert = rb_intern("cert");
  VALUE cert = rb_funcall(mini_ssl_ctx, sym_cert, 0);

  StringValue(cert);

  ID sym_ca = rb_intern("ca");
  VALUE ca = rb_funcall(mini_ssl_ctx, sym_ca, 0);

  ID sym_verify_mode = rb_intern("verify_mode");
  VALUE verify_mode = rb_funcall(mini_ssl_ctx, sym_verify_mode, 0);

  ID sym_verify_name = rb_intern("verify_name");
  VALUE verify_name = rb_funcall(mini_ssl_ctx, sym_verify_name, 0);

  ctx = SSL_CTX_new(SSLv23_server_method());
  conn->ctx = ctx;

  SSL_CTX_use_certificate_chain_file(ctx, RSTRING_PTR(cert));
  SSL_CTX_use_PrivateKey_file(ctx, RSTRING_PTR(key), SSL_FILETYPE_PEM);

  if (!NIL_P(ca)) {
    StringValue(ca);
    SSL_CTX_load_verify_locations(ctx, RSTRING_PTR(ca), NULL);
  }

  SSL_CTX_set_options(ctx, SSL_OP_CIPHER_SERVER_PREFERENCE | SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_SINGLE_DH_USE | SSL_OP_SINGLE_ECDH_USE | SSL_OP_NO_COMPRESSION);
  SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);

  SSL_CTX_set_cipher_list(ctx, "HIGH:!aNULL@STRENGTH");

  DH *dh = get_dh1024();
  SSL_CTX_set_tmp_dh(ctx, dh);

#ifndef OPENSSL_NO_ECDH
  EC_KEY *ecdh = EC_KEY_new_by_curve_name(NID_secp521r1);
  if (ecdh) {
    SSL_CTX_set_tmp_ecdh(ctx, ecdh);
    EC_KEY_free(ecdh);
  }
#endif

  ssl = SSL_new(ctx);
  conn->ssl = ssl;
  SSL_set_app_data(ssl, conn);

  int effective_verify_mode = NIL_P(verify_mode) ? SSL_VERIFY_NONE
                                                 : NUM2INT(verify_mode);

  /* Setting verify_name implies a required peer certificate */
  if (! NIL_P(verify_name)) {
    effective_verify_mode |= (SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT);
  }

  if (effective_verify_mode != SSL_VERIFY_NONE) {
    SSL_set_verify(ssl, effective_verify_mode, engine_verify_callback);
  }

  SSL_set_bio(ssl, conn->read, conn->write);

  SSL_set_accept_state(ssl);
  return obj;
}

VALUE engine_init_client(VALUE klass) {
  VALUE obj;
  ms_conn* conn = engine_alloc(klass, &obj);

  conn->ctx = SSL_CTX_new(DTLSv1_method());
  conn->ssl = SSL_new(conn->ctx);
  SSL_set_app_data(conn->ssl, conn);
  SSL_set_verify(conn->ssl, SSL_VERIFY_NONE, NULL);

  SSL_set_bio(conn->ssl, conn->read, conn->write);

  SSL_set_connect_state(conn->ssl);
  return obj;
}

VALUE engine_inject(VALUE self, VALUE str) {
  ms_conn* conn;
  long used;

  Data_Get_Struct(self, ms_conn, conn);

  StringValue(str);

  used = BIO_write(conn->read, RSTRING_PTR(str), (int)RSTRING_LEN(str));

  if(used == 0 || used == -1) {
    return Qfalse;
  }

  return INT2FIX(used);
}

static VALUE eError;

void raise_error(SSL* ssl, int result) {
  char buf[512];
  char msg[512];
  const char* err_str;
  int err = errno;
  int ssl_err = SSL_get_error(ssl, result);
  long verify_err = SSL_get_verify_result(ssl);

  if(SSL_ERROR_SYSCALL == ssl_err) {
    snprintf(msg, sizeof(msg), "System error: %s - %d", strerror(err), err);

  } else if(SSL_ERROR_SSL == ssl_err) {
    if(X509_V_OK != verify_err) {
      err_str = X509_verify_cert_error_string(verify_err);
      snprintf(msg, sizeof(msg),
               "OpenSSL certificate verification error: %s - %ld",
               err_str, verify_err);

    } else {
      unsigned long ssl_err = ERR_get_error();
      ERR_error_string_n(ssl_err, buf, sizeof(buf));
      snprintf(msg, sizeof(msg), "OpenSSL error: %s - %lu", buf, ssl_err);

    }
  } else {
    snprintf(msg, sizeof(msg), "Unknown OpenSSL error: %d", ssl_err);
  }

  ERR_clear_error();
  rb_raise(eError, "%s", msg);
}

VALUE engine_read(VALUE self) {
  ms_conn* conn;
  char buf[512];
  int bytes, error;

  Data_Get_Struct(self, ms_conn, conn);

  ERR_clear_error();

  bytes = SSL_read(conn->ssl, (void*)buf, sizeof(buf));

  if(bytes > 0) {
    return rb_str_new(buf, bytes);
  }

  if(SSL_want_read(conn->ssl)) return Qnil;

  error = SSL_get_error(conn->ssl, bytes);

  if(error == SSL_ERROR_ZERO_RETURN) {
    rb_eof_error();
  } else {
    raise_error(conn->ssl, bytes);
  }

  return Qnil;
}

VALUE engine_write(VALUE self, VALUE str) {
  ms_conn* conn;
  int bytes;

  Data_Get_Struct(self, ms_conn, conn);

  StringValue(str);

  ERR_clear_error();

  bytes = SSL_write(conn->ssl, (void*)RSTRING_PTR(str), (int)RSTRING_LEN(str));
  if(bytes > 0) {
    return INT2FIX(bytes);
  }

  if(SSL_want_write(conn->ssl)) return Qnil;

  raise_error(conn->ssl, bytes);

  return Qnil;
}

VALUE engine_extract(VALUE self) {
  ms_conn* conn;
  int bytes;
  size_t pending;
  char buf[512];

  Data_Get_Struct(self, ms_conn, conn);

  pending = BIO_pending(conn->write);
  if(pending > 0) {
    bytes = BIO_read(conn->write, buf, sizeof(buf));
    if(bytes > 0) {
      return rb_str_new(buf, bytes);
    } else if(!BIO_should_retry(conn->write)) {
      raise_error(conn->ssl, bytes);
    }
  }

  return Qnil;
}

VALUE engine_shutdown(VALUE self) {
  ms_conn* conn;
  int ok;

  Data_Get_Struct(self, ms_conn, conn);

  ERR_clear_error();

  ok = SSL_shutdown(conn->ssl);
  if (ok == 0) {
    return Qfalse;
  }

  return Qtrue;
}

VALUE engine_init(VALUE self) {
  ms_conn* conn;

  Data_Get_Struct(self, ms_conn, conn);

  return SSL_in_init(conn->ssl) ? Qtrue : Qfalse;
}

VALUE engine_peercert(VALUE self) {
  ms_conn* conn;
  X509* cert;
  int bytes;
  unsigned char* buf = NULL;
  ms_cert_buf* cert_buf = NULL;
  VALUE rb_cert_buf;

  Data_Get_Struct(self, ms_conn, conn);

  cert = SSL_get_peer_certificate(conn->ssl);
  if(!cert) {
    /*
     * See if there was a failed certificate associated with this client.
     */
    cert_buf = conn->failed_cert;
    if(!cert_buf) {
      return Qnil;
    }
    buf = cert_buf->buf;
    bytes = cert_buf->bytes;

  } else {
    bytes = i2d_X509(cert, &buf);
    X509_free(cert);

    if(bytes < 0) {
      return Qnil;
    }
  }

  rb_cert_buf = rb_str_new((const char*)(buf), bytes);
  if(!cert_buf) {
    OPENSSL_free(buf);
  }

  return rb_cert_buf;
}

VALUE noop(VALUE self) {
  return Qnil;
}

void Init_mini_ssl(VALUE puma) {
  VALUE mod, eng;

  SSL_library_init();
  OpenSSL_add_ssl_algorithms();
  SSL_load_error_strings();
  ERR_load_crypto_strings();

  mod = rb_define_module_under(puma, "MiniSSL");
  eng = rb_define_class_under(mod, "Engine", rb_cObject);

  rb_define_singleton_method(mod, "check", noop, 0);

  eError = rb_define_class_under(mod, "SSLError", rb_eStandardError);

  rb_define_singleton_method(eng, "server", engine_init_server, 1);
  rb_define_singleton_method(eng, "client", engine_init_client, 0);

  rb_define_method(eng, "inject", engine_inject, 1);
  rb_define_method(eng, "read",  engine_read, 0);

  rb_define_method(eng, "write",  engine_write, 1);
  rb_define_method(eng, "extract", engine_extract, 0);

  rb_define_method(eng, "shutdown", engine_shutdown, 0);

  rb_define_method(eng, "init?", engine_init, 0);

  rb_define_method(eng, "peercert", engine_peercert, 0);
}

#else

VALUE raise_error(VALUE self) {
  rb_raise(rb_eStandardError, "SSL not available in this build");
  return Qnil;
}

void Init_mini_ssl(VALUE puma) {
  VALUE mod, eng;

  mod = rb_define_module_under(puma, "MiniSSL");
  rb_define_class_under(mod, "SSLError", rb_eStandardError);

  rb_define_singleton_method(mod, "check", raise_error, 0);
}
#endif
