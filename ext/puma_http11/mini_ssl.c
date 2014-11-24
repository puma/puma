#define RSTRING_NOT_MODIFIED 1
#include <ruby.h>
#include <rubyio.h>
#include <openssl/bio.h>
#include <openssl/ssl.h>
#include <openssl/dh.h>
#include <openssl/err.h>

typedef struct {
  BIO* read;
  BIO* write;
  SSL* ssl;
  SSL_CTX* ctx;
} ms_conn;

void engine_free(ms_conn* conn) {
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
  dh->p = BN_bin2bn(dh1024_p, sizeof(dh1024_p), NULL);
  dh->g = BN_bin2bn(dh1024_g, sizeof(dh1024_g), NULL);

  if ((dh->p == NULL) || (dh->g == NULL)) {
    DH_free(dh);
    return NULL;
  }

  return dh;
}

VALUE engine_init_server(VALUE self, VALUE mini_ssl_ctx) {
  VALUE obj;
  SSL_CTX* ctx;
  SSL* ssl;

  ms_conn* conn = engine_alloc(self, &obj);

  ID sym_key = rb_intern("key");
  VALUE key = rb_funcall(mini_ssl_ctx, sym_key, 0);

  ID sym_cert = rb_intern("cert");
  VALUE cert = rb_funcall(mini_ssl_ctx, sym_cert, 0);

  ctx = SSL_CTX_new(SSLv23_server_method());
  conn->ctx = ctx;

  SSL_CTX_use_certificate_file(ctx, RSTRING_PTR(cert), SSL_FILETYPE_PEM);
  SSL_CTX_use_PrivateKey_file(ctx, RSTRING_PTR(key), SSL_FILETYPE_PEM);
  
  SSL_CTX_set_options(ctx, SSL_OP_CIPHER_SERVER_PREFERENCE | SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_SINGLE_DH_USE | SSL_OP_SINGLE_ECDH_USE);
  SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);

  SSL_CTX_set_cipher_list(ctx, "HIGH:!aNULL@STRENGTH");

  DH *dh = get_dh1024();
  SSL_CTX_set_tmp_dh(ctx, dh);

  EC_KEY *ecdh = EC_KEY_new_by_curve_name(NID_secp521r1);
  if (ecdh) {
    SSL_CTX_set_tmp_ecdh(ctx, ecdh);
    EC_KEY_free(ecdh);
  }

  ssl =  SSL_new(ctx);
  conn->ssl = ssl;

  /* SSL_set_verify(ssl, SSL_VERIFY_NONE, NULL); */

  SSL_set_bio(ssl, conn->read, conn->write);

  SSL_set_accept_state(ssl);
  return obj;
}

VALUE engine_init_client(VALUE klass) {
  VALUE obj;
  ms_conn* conn = engine_alloc(klass, &obj);

  conn->ctx = SSL_CTX_new(DTLSv1_method());
  conn->ssl = SSL_new(conn->ctx);
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
  int error = SSL_get_error(ssl, result);
  char* msg = ERR_error_string(error, NULL);

  ERR_clear_error();
  rb_raise(eError, "OpenSSL error: %s - %d", msg, error);
}

VALUE engine_read(VALUE self) {
  ms_conn* conn;
  char buf[512];
  int bytes, n;

  Data_Get_Struct(self, ms_conn, conn);

  bytes = SSL_read(conn->ssl, (void*)buf, sizeof(buf));

  if(bytes > 0) {
    return rb_str_new(buf, bytes);
  }

  if(SSL_want_read(conn->ssl)) return Qnil;

  if(SSL_get_error(conn->ssl, bytes) == SSL_ERROR_ZERO_RETURN) {
    rb_eof_error();
  }

  raise_error(conn->ssl, bytes);

  return Qnil;
}

VALUE engine_write(VALUE self, VALUE str) {
  ms_conn* conn;
  char buf[512];
  int bytes;

  Data_Get_Struct(self, ms_conn, conn);

  StringValue(str);

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

void Init_mini_ssl(VALUE puma) {
  VALUE mod, eng;

  SSL_library_init();
  OpenSSL_add_ssl_algorithms();
  SSL_load_error_strings();
  ERR_load_crypto_strings();
  
  mod = rb_define_module_under(puma, "MiniSSL");
  eng = rb_define_class_under(mod, "Engine", rb_cObject);

  eError = rb_define_class_under(mod, "SSLError", rb_eStandardError);

  rb_define_singleton_method(eng, "server", engine_init_server, 1);
  rb_define_singleton_method(eng, "client", engine_init_client, 0);

  rb_define_method(eng, "inject", engine_inject, 1);
  rb_define_method(eng, "read",  engine_read, 0);

  rb_define_method(eng, "write",  engine_write, 1);
  rb_define_method(eng, "extract", engine_extract, 0);
}
