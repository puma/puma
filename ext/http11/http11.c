#include "ruby.h"
#include "ext_help.h"
#include <assert.h>
#include <string.h>
#include "http11_parser.h"
#include <ctype.h>
#include "tst.h"

static VALUE mMongrel;
static VALUE cHttpParser;
static VALUE cURIClassifier;
static int id_handler_map;

static VALUE global_http_prefix;
static VALUE global_request_method;
static VALUE global_request_uri;
static VALUE global_query_string;
static VALUE global_http_version;
static VALUE global_content_length;
static VALUE global_http_content_length;
static VALUE global_content_type;
static VALUE global_http_content_type;
static VALUE global_gateway_interface;
static VALUE global_gateway_interface_value;
static VALUE global_interface_value;
static VALUE global_remote_address;
static VALUE global_server_name;
static VALUE global_server_port;
static VALUE global_server_protocol;
static VALUE global_server_protocol_value;
static VALUE global_http_host;
static VALUE global_mongrel_version;
static VALUE global_server_software;


void http_field(void *data, const char *field, size_t flen, const char *value, size_t vlen)
{
  char *ch, *end;
  VALUE req = (VALUE)data;
  VALUE v = rb_str_new(value, vlen);
  VALUE f = rb_str_dup(global_http_prefix);

  f = rb_str_buf_cat(f, field, flen); 
  
  for(ch = RSTRING(f)->ptr, end = ch + RSTRING(f)->len; ch < end; ch++) {
    if(*ch == '-') {
      *ch = '_';
    } else {
      *ch = toupper(*ch);
    }
  }

  rb_hash_aset(req, f, v);
}

void request_method(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  rb_hash_aset(req, global_request_method, val);
}

void request_uri(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  rb_hash_aset(req, global_request_uri, val);
}


void query_string(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
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
  VALUE host = Qnil;
  VALUE port = Qnil;
  char *colon = NULL;

  rb_hash_aset(req, global_content_length, rb_hash_aref(req, global_http_content_length));
  rb_hash_aset(req, global_content_type, rb_hash_aref(req, global_http_content_type));
  rb_hash_aset(req, global_gateway_interface, global_gateway_interface_value);
  if((temp = rb_hash_aref(req, global_http_host)) != Qnil) {
    // ruby better close strings off with a '\0' dammit
    colon = strchr(RSTRING(temp)->ptr, ':');
    if(colon != NULL) {
      rb_hash_aset(req, global_server_name, rb_str_substr(temp, 0, colon - RSTRING(temp)->ptr));
      rb_hash_aset(req, global_server_port, 
		   rb_str_substr(temp, colon - RSTRING(temp)->ptr+1, 
				 RSTRING(temp)->len));
    }
  }

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
    hp->query_string = query_string;
    hp->http_version = http_version;
    hp->header_done = header_done;

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
 *    parser.execute(req_hash, data) -> Integer
 *
 * Takes a Hash and a String of data, parses the String of data filling in the Hash
 * returning an Integer to indicate how much of the data has been read.  No matter
 * what the return value, you should call HttpParser#finished? and HttpParser#error?
 * to figure out if it's done parsing or there was an error.
 * 
 * This function now throws an exception when there is a parsing error.  This makes 
 * the logic for working with the parser much easier.  You can still test for an 
 * error, but now you need to wrap the parser with an exception handling block.
 */
VALUE HttpParser_execute(VALUE self, VALUE req_hash, VALUE data)
{
  http_parser *http = NULL;
  DATA_GET(self, http_parser, http);

  http->data = (void *)req_hash;
  http_parser_execute(http, RSTRING(data)->ptr, RSTRING(data)->len);

  if(http_parser_has_error(http)) {
    rb_raise(rb_eStandardError, "HTTP Parsing failure");
  } else {
    return INT2FIX(http_parser_nread(http));
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


void URIClassifier_free(void *data) 
{
    TRACE();
    
    if(data) {
      tst_cleanup((struct tst *)data);
    }
}


#define TRIE_INCREASE 30

VALUE URIClassifier_alloc(VALUE klass)
{
    VALUE obj;
    struct tst *tst = tst_init(TRIE_INCREASE);
    TRACE();
    assert(tst && "failed to initialize trie structure");

    obj = Data_Wrap_Struct(klass, NULL, URIClassifier_free, tst);

    return obj;
}

/**
 * call-seq:
 *    URIClassifier.new -> URIClassifier
 *
 * Initializes a new URIClassifier object that you can use to associate URI sequences
 * with objects.  You can actually use it with any string sequence and any objects,
 * but it's mostly used with URIs.
 *
 * It uses TST from http://www.octavian.org/cs/software.html to build an ternary search
 * trie to hold all of the URIs.  It uses this to do an initial search for the a URI
 * prefix, and then to break the URI into SCRIPT_NAME and PATH_INFO portions.  It actually
 * will do two searches most of the time in order to find the right handler for the
 * registered prefix portion.
 *
 */
VALUE URIClassifier_init(VALUE self)
{
  VALUE hash;

  // we create an internal hash to protect stuff from the GC
  hash = rb_hash_new();
  rb_ivar_set(self, id_handler_map, hash);

  return self;
}


/**
 * call-seq:
 *    uc.register("/someuri", SampleHandler.new) -> nil
 *
 * Registers the SampleHandler (one for all requests) with the "/someuri".
 * When URIClassifier::resolve is called with "/someuri" it'll return
 * SampleHandler immediately.  When called with "/someuri/iwant" it'll also
 * return SomeHandler immediatly, with no additional searches, but it will
 * return path info with "/iwant".
 *
 * You actually can reuse this class to register nearly anything and 
 * quickly resolve it.  This could be used for caching, fast mapping, etc.
 * The downside is it uses much more memory than a Hash, but it can be
 * a lot faster.  It's main advantage is that it works on prefixes, which
 * is damn hard to get right with a Hash.
 */
VALUE URIClassifier_register(VALUE self, VALUE uri, VALUE handler)
{
  int rc = 0;
  void *ptr = NULL;
  struct tst *tst = NULL;
  DATA_GET(self, struct tst, tst);

  rc = tst_insert((unsigned char *)StringValueCStr(uri), (void *)handler , tst, 0, &ptr);

  if(rc == TST_DUPLICATE_KEY) {
    rb_raise(rb_eStandardError, "Handler already registered with that name");
  } else if(rc == TST_ERROR) {
    rb_raise(rb_eStandardError, "Memory error registering handler");
  } else if(rc == TST_NULL_KEY) {
    rb_raise(rb_eStandardError, "URI was empty");
  }
  
  rb_hash_aset(rb_ivar_get(self, id_handler_map), uri, handler);

  return Qnil;
}


/**
 * call-seq:
 *    uc.unregister("/someuri")
 *
 * Yep, just removes this uri and it's handler from the trie.
 */
VALUE URIClassifier_unregister(VALUE self, VALUE uri)
{
  void *handler = NULL;
  struct tst *tst = NULL;
  DATA_GET(self, struct tst, tst);

  handler = tst_delete((unsigned char *)StringValueCStr(uri), tst);

  if(handler) {
    rb_hash_delete(rb_ivar_get(self, id_handler_map), uri);

    return (VALUE)handler;
  } else {
    return Qnil;
  }
}


/**
 * call-seq:
 *    uc.resolve("/someuri") -> "/someuri", "", handler
 *    uc.resolve("/someuri/pathinfo") -> "/someuri", "/pathinfo", handler
 *    uc.resolve("/notfound/orhere") -> nil, nil, nil
 *    uc.resolve("/") -> "/", "/", handler  # if uc.register("/", handler)
 *    uc.resolve("/path/from/root") -> "/", "/path/from/root", handler  # if uc.register("/", handler) 
 * 
 * Attempts to resolve either the whole URI or at the longest prefix, returning
 * the prefix (as script_info), path (as path_info), and registered handler
 * (usually an HttpHandler).  If it doesn't find a handler registered at the longest
 * match then it returns nil,nil,nil.
 *
 * Because the resolver uses a trie you are able to register a handler at *any* character
 * in the URI and it will be handled as long as it's the longest prefix.  So, if you 
 * registered handler #1 at "/something/lik", and #2 at "/something/like/that", then a
 * a search for "/something/like" would give you #1.  A search for "/something/like/that/too"
 * would give you #2.
 * 
 * This is very powerful since it means you can also attach handlers to parts of the ; 
 * (semi-colon) separated path params, any part of the path, use off chars, anything really.
 * It also means that it's very efficient to do this only taking as long as the URI has
 * characters.
 *
 * A slight modification to the CGI 1.2 standard is given for handlers registered to "/".
 * CGI expects all CGI scripts to be at some script path, so it doesn't really say anything
 * about a script that handles the root.  To make this work, the resolver will detect that
 * the requested handler is at "/", and return that for script_name, and then simply return
 * the full URI back as path_info.
 *
 * It expects strings with no embedded '\0' characters.  Don't try other string-like stuff yet.
 */
VALUE URIClassifier_resolve(VALUE self, VALUE uri)
{
  void *handler = NULL;
  int pref_len = 0;
  struct tst *tst = NULL;
  VALUE result;
  unsigned char *uri_str = NULL;

  DATA_GET(self, struct tst, tst);
  uri_str = (unsigned char *)StringValueCStr(uri);

  handler = tst_search(uri_str, tst, &pref_len);

  // setup for multiple return values
  result = rb_ary_new();

  if(handler) {
    rb_ary_push(result, rb_str_substr (uri, 0, pref_len));
    // compensate for a script_name="/" where we need to add the "/" to path_info to keep it consistent
    if(pref_len == 1 && uri_str[0] == '/') {
      // matches the root URI so we have to use the whole URI as the path_info
      rb_ary_push(result, uri);
    } else {
      // matches a script so process like normal
      rb_ary_push(result, rb_str_substr(uri, pref_len, RSTRING(uri)->len));
    }
      
    rb_ary_push(result, (VALUE)handler);
  } else {
    // not found so push back nothing
    rb_ary_push(result, Qnil);
    rb_ary_push(result, Qnil);
    rb_ary_push(result, Qnil);
  }

  return result;
}

#define DEF_GLOBAL(name, val)   global_##name = rb_str_new2(val); rb_global_variable(&global_##name)


void Init_http11()
{

  mMongrel = rb_define_module("Mongrel");
  id_handler_map = rb_intern("@handler_map");

  DEF_GLOBAL(http_prefix, "HTTP_");
  DEF_GLOBAL(request_method, "REQUEST_METHOD");
  DEF_GLOBAL(request_uri, "REQUEST_URI");
  DEF_GLOBAL(query_string, "QUERY_STRING");
  DEF_GLOBAL(http_version, "HTTP_VERSION");
  DEF_GLOBAL(content_length, "CONTENT_LENGTH");
  DEF_GLOBAL(http_content_length, "HTTP_CONTENT_LENGTH");
  DEF_GLOBAL(content_type, "CONTENT_TYPE");
  DEF_GLOBAL(http_content_type, "HTTP_CONTENT_TYPE");
  DEF_GLOBAL(gateway_interface, "GATEWAY_INTERFACE");
  DEF_GLOBAL(gateway_interface_value, "CGI/1.2");
  DEF_GLOBAL(remote_address, "REMOTE_ADDR");
  DEF_GLOBAL(server_name, "SERVER_NAME");
  DEF_GLOBAL(server_port, "SERVER_PORT");
  DEF_GLOBAL(server_protocol, "SERVER_PROTOCOL");
  DEF_GLOBAL(server_protocol_value, "HTTP/1.1");
  DEF_GLOBAL(http_host, "HTTP_HOST");
  DEF_GLOBAL(mongrel_version, "Mongrel 0.3.12");
  DEF_GLOBAL(server_software, "SERVER_SOFTWARE");


  cHttpParser = rb_define_class_under(mMongrel, "HttpParser", rb_cObject);
  rb_define_alloc_func(cHttpParser, HttpParser_alloc);
  rb_define_method(cHttpParser, "initialize", HttpParser_init,0);
  rb_define_method(cHttpParser, "reset", HttpParser_reset,0);
  rb_define_method(cHttpParser, "finish", HttpParser_finish,0);
  rb_define_method(cHttpParser, "execute", HttpParser_execute,2);
  rb_define_method(cHttpParser, "error?", HttpParser_has_error,0);
  rb_define_method(cHttpParser, "finished?", HttpParser_is_finished,0);
  rb_define_method(cHttpParser, "nread", HttpParser_nread,0);

  cURIClassifier = rb_define_class_under(mMongrel, "URIClassifier", rb_cObject);
  rb_define_alloc_func(cURIClassifier, URIClassifier_alloc);
  rb_define_method(cURIClassifier, "initialize", URIClassifier_init, 0);
  rb_define_method(cURIClassifier, "register", URIClassifier_register, 2);
  rb_define_method(cURIClassifier, "unregister", URIClassifier_unregister, 1);
  rb_define_method(cURIClassifier, "resolve", URIClassifier_resolve, 1);
}
 

