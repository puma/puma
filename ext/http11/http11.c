/**
 * Copyright (c) 2005 Zed A. Shaw
 * You can redistribute it and/or modify it under the same terms as Ruby.
 */
#include "ruby.h"
#include "ext_help.h"
#include <assert.h>
#include <string.h>
#include "http11_parser.h"

#ifndef RSTRING_PTR
#define RSTRING_PTR(s) (RSTRING(s)->ptr)
#endif
#ifndef RSTRING_LEN
#define RSTRING_LEN(s) (RSTRING(s)->len)
#endif

#ifndef RSTRING_PTR
#define RSTRING_PTR(s) (RSTRING(s)->ptr)
#endif
#ifndef RSTRING_LEN
#define RSTRING_LEN(s) (RSTRING(s)->len)
#endif

static VALUE mMongrel;
static VALUE cHttpParser;
static VALUE eHttpParserError;

#define id_handler_map rb_intern("@handler_map")
#define id_http_body rb_intern("@http_body")
#define HTTP_PREFIX "HTTP_"
#define HTTP_PREFIX_LEN (sizeof(HTTP_PREFIX) - 1)

static VALUE global_request_method;
static VALUE global_request_uri;
static VALUE global_fragment;
static VALUE global_query_string;
static VALUE global_http_version;
static VALUE global_content_length;
static VALUE global_http_content_length;
static VALUE global_request_path;
static VALUE global_content_type;
static VALUE global_http_content_type;
static VALUE global_gateway_interface;
static VALUE global_gateway_interface_value;
static VALUE global_server_name;
static VALUE global_server_port;
static VALUE global_server_protocol;
static VALUE global_server_protocol_value;
static VALUE global_http_host;
static VALUE global_mongrel_version;
static VALUE global_server_software;
static VALUE global_port_80;

#define TRIE_INCREASE 30

/** Defines common length and error messages for input length validation. */
#define DEF_MAX_LENGTH(N,length) const size_t MAX_##N##_LENGTH = length; const char *MAX_##N##_LENGTH_ERR = "HTTP element " # N  " is longer than the " # length " allowed length."

/** Validates the max length of given input and throws an HttpParserError exception if over. */
#define VALIDATE_MAX_LENGTH(len, N) if(len > MAX_##N##_LENGTH) { rb_raise(eHttpParserError, MAX_##N##_LENGTH_ERR); }

/** Defines global strings in the init method. */
#define DEF_GLOBAL(N, val)   global_##N = rb_obj_freeze(rb_str_new2(val)); rb_global_variable(&global_##N)


/* Defines the maximum allowed lengths for various input elements.*/
DEF_MAX_LENGTH(FIELD_NAME, 256);
DEF_MAX_LENGTH(FIELD_VALUE, 80 * 1024);
DEF_MAX_LENGTH(REQUEST_URI, 1024 * 12);
DEF_MAX_LENGTH(FRAGMENT, 1024); /* Don't know if this length is specified somewhere or not */
DEF_MAX_LENGTH(REQUEST_PATH, 1024);
DEF_MAX_LENGTH(QUERY_STRING, (1024 * 10));
DEF_MAX_LENGTH(HEADER, (1024 * (80 + 32)));

struct common_field {
	const signed long len;
	const char *name;
	VALUE value;
};

/*
 * A list of common HTTP headers we expect to receive.
 * This allows us to avoid repeatedly creating identical string
 * objects to be used with rb_hash_aset().
 */
static struct common_field common_http_fields[] = {
# define f(N) { (sizeof(N) - 1), N, Qnil }
	f("ACCEPT"),
	f("ACCEPT_CHARSET"),
	f("ACCEPT_ENCODING"),
	f("ACCEPT_LANGUAGE"),
	f("ALLOW"),
	f("AUTHORIZATION"),
	f("CACHE_CONTROL"),
	f("CONNECTION"),
	f("CONTENT_ENCODING"),
	f("CONTENT_LENGTH"),
	f("CONTENT_TYPE"),
	f("COOKIE"),
	f("DATE"),
	f("EXPECT"),
	f("FROM"),
	f("HOST"),
	f("IF_MATCH"),
	f("IF_MODIFIED_SINCE"),
	f("IF_NONE_MATCH"),
	f("IF_RANGE"),
	f("IF_UNMODIFIED_SINCE"),
	f("KEEP_ALIVE"), /* Firefox sends this */
	f("MAX_FORWARDS"),
	f("PRAGMA"),
	f("PROXY_AUTHORIZATION"),
	f("RANGE"),
	f("REFERER"),
	f("TE"),
	f("TRAILER"),
	f("TRANSFER_ENCODING"),
	f("UPGRADE"),
	f("USER_AGENT"),
	f("VIA"),
	f("X_FORWARDED_FOR"), /* common for proxies */
	f("X_REAL_IP"), /* common for proxies */
	f("WARNING")
# undef f
};

/*
 * qsort(3) and bsearch(3) improve average performance slightly, but may
 * not be worth it for lack of portability to certain platforms...
 */
#if defined(HAVE_QSORT_BSEARCH)
/* sort by length, then by name if there's a tie */
static int common_field_cmp(const void *a, const void *b)
{
  struct common_field *cfa = (struct common_field *)a;
  struct common_field *cfb = (struct common_field *)b;
  signed long diff = cfa->len - cfb->len;
  return diff ? diff : memcmp(cfa->name, cfb->name, cfa->len);
}
#endif /* HAVE_QSORT_BSEARCH */

static void init_common_fields(void)
{
  int i;
  struct common_field *cf = common_http_fields;
  char tmp[256]; /* MAX_FIELD_NAME_LENGTH */
  memcpy(tmp, HTTP_PREFIX, HTTP_PREFIX_LEN);

  for(i = 0; i < ARRAY_SIZE(common_http_fields); cf++, i++) {
    memcpy(tmp + HTTP_PREFIX_LEN, cf->name, cf->len + 1);
    cf->value = rb_obj_freeze(rb_str_new(tmp, HTTP_PREFIX_LEN + cf->len));
    rb_global_variable(&cf->value);
  }

#if defined(HAVE_QSORT_BSEARCH)
  qsort(common_http_fields,
        ARRAY_SIZE(common_http_fields),
        sizeof(struct common_field),
        common_field_cmp);
#endif /* HAVE_QSORT_BSEARCH */
}

static VALUE find_common_field_value(const char *field, size_t flen)
{
#if defined(HAVE_QSORT_BSEARCH)
  struct common_field key;
  struct common_field *found;
  key.name = field;
  key.len = (signed long)flen;
  found = (struct common_field *)bsearch(&key, common_http_fields,
                                         ARRAY_SIZE(common_http_fields),
                                         sizeof(struct common_field),
                                         common_field_cmp);
  return found ? found->value : Qnil;
#else /* !HAVE_QSORT_BSEARCH */
  int i;
  struct common_field *cf = common_http_fields;
  for(i = 0; i < ARRAY_SIZE(common_http_fields); i++, cf++) {
    if (cf->len == flen && !memcmp(cf->name, field, flen))
      return cf->value;
  }
  return Qnil;
#endif /* !HAVE_QSORT_BSEARCH */
}

void http_field(void *data, const char *field, size_t flen, const char *value, size_t vlen)
{
  VALUE req = (VALUE)data;
  VALUE v = Qnil;
  VALUE f = Qnil;

  VALIDATE_MAX_LENGTH(flen, FIELD_NAME);
  VALIDATE_MAX_LENGTH(vlen, FIELD_VALUE);

  v = rb_str_new(value, vlen);

  f = find_common_field_value(field, flen);

  if (f == Qnil) {
    /*
     * We got a strange header that we don't have a memoized value for.
     * Fallback to creating a new string to use as a hash key.
     *
     * using rb_str_new(NULL, len) here is faster than rb_str_buf_new(len)
     * in my testing, because: there's no minimum allocation length (and
     * no check for it, either), RSTRING_LEN(f) does not need to be
     * written twice, and and RSTRING_PTR(f) will already be
     * null-terminated for us.
     */
    f = rb_str_new(NULL, HTTP_PREFIX_LEN + flen);
    memcpy(RSTRING_PTR(f), HTTP_PREFIX, HTTP_PREFIX_LEN);
    memcpy(RSTRING_PTR(f) + HTTP_PREFIX_LEN, field, flen);
    assert(*(RSTRING_PTR(f) + RSTRING_LEN(f)) == '\0'); /* paranoia */
    /* fprintf(stderr, "UNKNOWN HEADER <%s>\n", RSTRING_PTR(f)); */
  }

  rb_hash_aset(req, f, v);
}

void request_method(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = Qnil;

  val = rb_str_new(at, length);
  rb_hash_aset(req, global_request_method, val);
}

void request_uri(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = Qnil;

  VALIDATE_MAX_LENGTH(length, REQUEST_URI);

  val = rb_str_new(at, length);
  rb_hash_aset(req, global_request_uri, val);
}

void fragment(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = Qnil;

  VALIDATE_MAX_LENGTH(length, FRAGMENT);

  val = rb_str_new(at, length);
  rb_hash_aset(req, global_fragment, val);
}

void request_path(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = Qnil;

  VALIDATE_MAX_LENGTH(length, REQUEST_PATH);

  val = rb_str_new(at, length);
  rb_hash_aset(req, global_request_path, val);
}

void query_string(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = Qnil;

  VALIDATE_MAX_LENGTH(length, QUERY_STRING);

  val = rb_str_new(at, length);
  rb_hash_aset(req, global_query_string, val);
}

void http_version(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  rb_hash_aset(req, global_http_version, val);
}

/** Finalizes the request header to have a bunch of stuff that's
  needed. */

void header_done(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE temp = Qnil;
  VALUE ctype = Qnil;
  VALUE clen = Qnil;
  char *colon = NULL;

  clen = rb_hash_aref(req, global_http_content_length);
  if(clen != Qnil) {
    rb_hash_aset(req, global_content_length, clen);
  }

  ctype = rb_hash_aref(req, global_http_content_type);
  if(ctype != Qnil) {
    rb_hash_aset(req, global_content_type, ctype);
  }

  rb_hash_aset(req, global_gateway_interface, global_gateway_interface_value);
  if((temp = rb_hash_aref(req, global_http_host)) != Qnil) {
    colon = memchr(RSTRING_PTR(temp), ':', RSTRING_LEN(temp));
    if(colon != NULL) {
      rb_hash_aset(req, global_server_name, rb_str_substr(temp, 0, colon - RSTRING_PTR(temp)));
      rb_hash_aset(req, global_server_port, 
          rb_str_substr(temp, colon - RSTRING_PTR(temp)+1, 
            RSTRING_LEN(temp)));
    } else {
      rb_hash_aset(req, global_server_name, temp);
      rb_hash_aset(req, global_server_port, global_port_80);
    }
  }

  /* grab the initial body and stuff it into an ivar */
  rb_ivar_set(req, id_http_body, rb_str_new(at, length));
  rb_hash_aset(req, global_server_protocol, global_server_protocol_value);
  rb_hash_aset(req, global_server_software, global_mongrel_version);
}


void HttpParser_free(void *data) {
  TRACE();

  if(data) {
    free(data);
  }
}


VALUE HttpParser_alloc(VALUE klass)
{
  VALUE obj;
  http_parser *hp = ALLOC_N(http_parser, 1);
  TRACE();
  hp->http_field = http_field;
  hp->request_method = request_method;
  hp->request_uri = request_uri;
  hp->fragment = fragment;
  hp->request_path = request_path;
  hp->query_string = query_string;
  hp->http_version = http_version;
  hp->header_done = header_done;
  http_parser_init(hp);

  obj = Data_Wrap_Struct(klass, NULL, HttpParser_free, hp);

  return obj;
}


/**
 * call-seq:
 *    parser.new -> parser
 *
 * Creates a new parser.
 */
VALUE HttpParser_init(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);
  http_parser_init(http);

  return self;
}


/**
 * call-seq:
 *    parser.reset -> nil
 *
 * Resets the parser to it's initial state so that you can reuse it
 * rather than making new ones.
 */
VALUE HttpParser_reset(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);
  http_parser_init(http);

  return Qnil;
}


/**
 * call-seq:
 *    parser.finish -> true/false
 *
 * Finishes a parser early which could put in a "good" or bad state.
 * You should call reset after finish it or bad things will happen.
 */
VALUE HttpParser_finish(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);
  http_parser_finish(http);

  return http_parser_is_finished(http) ? Qtrue : Qfalse;
}


/**
 * call-seq:
 *    parser.execute(req_hash, data, start) -> Integer
 *
 * Takes a Hash and a String of data, parses the String of data filling in the Hash
 * returning an Integer to indicate how much of the data has been read.  No matter
 * what the return value, you should call HttpParser#finished? and HttpParser#error?
 * to figure out if it's done parsing or there was an error.
 * 
 * This function now throws an exception when there is a parsing error.  This makes 
 * the logic for working with the parser much easier.  You can still test for an 
 * error, but now you need to wrap the parser with an exception handling block.
 *
 * The third argument allows for parsing a partial request and then continuing
 * the parsing from that position.  It needs all of the original data as well 
 * so you have to append to the data buffer as you read.
 */
VALUE HttpParser_execute(VALUE self, VALUE req_hash, VALUE data, VALUE start)
{
  http_parser *http = NULL;
  int from = 0;
  char *dptr = NULL;
  long dlen = 0;

  DATA_GET(self, http_parser, http);

  from = FIX2INT(start);
  dptr = RSTRING_PTR(data);
  dlen = RSTRING_LEN(data);

  if(from >= dlen) {
    rb_raise(eHttpParserError, "Requested start is after data buffer end.");
  } else {
    http->data = (void *)req_hash;
    http_parser_execute(http, dptr, dlen, from);

    VALIDATE_MAX_LENGTH(http_parser_nread(http), HEADER);

    if(http_parser_has_error(http)) {
      rb_raise(eHttpParserError, "Invalid HTTP format, parsing fails.");
    } else {
      return INT2FIX(http_parser_nread(http));
    }
  }
}



/**
 * call-seq:
 *    parser.error? -> true/false
 *
 * Tells you whether the parser is in an error state.
 */
VALUE HttpParser_has_error(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);

  return http_parser_has_error(http) ? Qtrue : Qfalse;
}


/**
 * call-seq:
 *    parser.finished? -> true/false
 *
 * Tells you whether the parser is finished or not and in a good state.
 */
VALUE HttpParser_is_finished(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);

  return http_parser_is_finished(http) ? Qtrue : Qfalse;
}


/**
 * call-seq:
 *    parser.nread -> Integer
 *
 * Returns the amount of data processed so far during this processing cycle.  It is
 * set to 0 on initialize or reset calls and is incremented each time execute is called.
 */
VALUE HttpParser_nread(VALUE self)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);

  return INT2FIX(http->nread);
}

void Init_http11()
{

  mMongrel = rb_define_module("Mongrel");

  DEF_GLOBAL(request_method, "REQUEST_METHOD");
  DEF_GLOBAL(request_uri, "REQUEST_URI");
  DEF_GLOBAL(fragment, "FRAGMENT");
  DEF_GLOBAL(query_string, "QUERY_STRING");
  DEF_GLOBAL(http_version, "HTTP_VERSION");
  DEF_GLOBAL(request_path, "REQUEST_PATH");
  DEF_GLOBAL(content_length, "CONTENT_LENGTH");
  DEF_GLOBAL(http_content_length, "HTTP_CONTENT_LENGTH");
  DEF_GLOBAL(content_type, "CONTENT_TYPE");
  DEF_GLOBAL(http_content_type, "HTTP_CONTENT_TYPE");
  DEF_GLOBAL(gateway_interface, "GATEWAY_INTERFACE");
  DEF_GLOBAL(gateway_interface_value, "CGI/1.2");
  DEF_GLOBAL(server_name, "SERVER_NAME");
  DEF_GLOBAL(server_port, "SERVER_PORT");
  DEF_GLOBAL(server_protocol, "SERVER_PROTOCOL");
  DEF_GLOBAL(server_protocol_value, "HTTP/1.1");
  DEF_GLOBAL(http_host, "HTTP_HOST");
  DEF_GLOBAL(mongrel_version, "Mongrel 1.2.0.pre2"); /* XXX Why is this defined here? */
  DEF_GLOBAL(server_software, "SERVER_SOFTWARE");
  DEF_GLOBAL(port_80, "80");

  eHttpParserError = rb_define_class_under(mMongrel, "HttpParserError", rb_eIOError);

  cHttpParser = rb_define_class_under(mMongrel, "HttpParser", rb_cObject);
  rb_define_alloc_func(cHttpParser, HttpParser_alloc);
  rb_define_method(cHttpParser, "initialize", HttpParser_init,0);
  rb_define_method(cHttpParser, "reset", HttpParser_reset,0);
  rb_define_method(cHttpParser, "finish", HttpParser_finish,0);
  rb_define_method(cHttpParser, "execute", HttpParser_execute,3);
  rb_define_method(cHttpParser, "error?", HttpParser_has_error,0);
  rb_define_method(cHttpParser, "finished?", HttpParser_is_finished,0);
  rb_define_method(cHttpParser, "nread", HttpParser_nread,0);
  init_common_fields();
}
