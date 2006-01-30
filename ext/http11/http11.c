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


void http_field(void *data, const char *field, size_t flen, const char *value, size_t vlen)
{
  char *ch, *end;
  VALUE req = (VALUE)data;
  VALUE f = rb_str_new2("HTTP_");
  VALUE v = rb_str_new(value, vlen);
  
  rb_str_buf_cat(f, field, flen); 
  
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
  VALUE id = rb_str_new2("REQUEST_METHOD");
  rb_hash_aset(req, id, val);
}

void path_info(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  VALUE id = rb_str_new2("PATH_INFO");
  rb_hash_aset(req, id, val);
}


void query_string(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  VALUE id = rb_str_new2("QUERY_STRING");
  rb_hash_aset(req, id, val);
}

void http_version(void *data, const char *at, size_t length)
{
  VALUE req = (VALUE)data;
  VALUE val = rb_str_new(at, length);
  VALUE id = rb_str_new2("HTTP_VERSION");
  rb_hash_aset(req, id, val);
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
    http_parser *hp = calloc(1, sizeof(http_parser));
    TRACE();
    hp->http_field = http_field;
    hp->request_method = request_method;
    hp->path_info = path_info;
    hp->query_string = query_string;
    hp->http_version = http_version;
    
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
 * Here's how it all works.  Let's say you register "/blog" with a BlogHandler.  Great.
 * Now, someone goes to "/blog/zedsucks/ass".  You want SCRIPT_NAME to be "/blog" and
 * PATH_INFO to be "/zedsucks/ass".  URIClassifier first does a TST search and comes
 * up with a failure, but knows that the failure ended at the "/blog" part.  So, that's
 * the SCRIPT_NAME.  It then tries a second search for just "/blog".  If that comes back
 * good then it sets the rest ("/zedsucks/ass") to the PATH_INFO and returns the BlogHandler.
 *
 * The optimal approach would be to not do the search twice, but the TST lib doesn't
 * really support returning prefixes.  Might not be hard to add later.
 *
 * The key though is that it will try to match the *longest* match it can.  If you 
 * also register "/blog/zed" then the above URI will give SCRIPT_NAME="/blog/zed", 
 * PATH_INFO="sucks/ass".  Probably not what you want, so your handler will need to
 * do the 404 thing.
 *
 * Take a look at the postamble of example/tepee.rb to see how this is handled for
 * Camping. 
 */
VALUE URIClassifier_init(VALUE self)
{
  VALUE hash;

  // we create an internal hash to protect stuff from the GC
  hash = rb_hash_new();
  rb_iv_set(self, "handler_map", hash);
}


/**
 * call-seq:
 *    uc.register("/someuri", SampleHandler.new) -> nil
 *
 * Registers the SampleHandler (one for all requests) with the "/someuri".
 * When URIClassifier::resolve is called with "/someuri" it'll return
 * SampleHandler immediately.  When "/someuri/pathhere" is called it'll
 * find SomeHandler after a second search, and setup PATH_INFO="/pathhere".
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
  
  rb_hash_aset(rb_iv_get(self, "handler_map"), uri, handler);

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
    rb_hash_delete(rb_iv_get(self, "handler_map"), uri);

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
 *
 * Attempts to resolve either the whole URI or at the longest prefix, returning
 * the prefix (as script_info), path (as path_info), and registered handler
 * (usually an HttpHandler).
 *
 * It expects strings.  Don't try other string-line stuff yet.
 */
VALUE URIClassifier_resolve(VALUE self, VALUE uri)
{
  void *handler = NULL;
  int pref_len = 0;
  struct tst *tst = NULL;
  VALUE result;
  VALUE script_name;
  VALUE path_info;
  unsigned char *uri_str = NULL;
  unsigned char *script_name_str = NULL;

  DATA_GET(self, struct tst, tst);
  uri_str = (unsigned char *)StringValueCStr(uri);

  handler = tst_search(uri_str, tst, &pref_len);

  // setup for multiple return values
  result = rb_ary_new();


  if(handler == NULL) {
    script_name = rb_str_substr (uri, 0, pref_len);
    script_name_str = (unsigned char *)StringValueCStr(script_name);

    handler = tst_search(script_name_str, tst, NULL);

    if(handler == NULL) {
      // didn't find the script name at all
      rb_ary_push(result, Qnil);
      rb_ary_push(result, Qnil);
      rb_ary_push(result, Qnil);
      return result;
    } else {
      // found a handler, setup the path info and we're good
      path_info = rb_str_substr(uri, pref_len, RSTRING(uri)->len);
    }
  } else {
    // whole thing was found, so uri is the script name, path info empty
    script_name = uri;
    path_info = rb_str_new2("");
  }

  rb_ary_push(result, script_name);
  rb_ary_push(result, path_info);
  rb_ary_push(result, (VALUE)handler);
  return result;
}



void Init_http11()
{
    
  TRACE();
  
  mMongrel = rb_define_module("Mongrel");
  
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
 

