#ifndef http11_parser_h
#define http11_parser_h

#include <sys/types.h>

#if defined(_WIN32)
#include <stddef.h>
#endif

typedef void (*element_cb)(void *data, const char *at, size_t length);
typedef void (*field_cb)(void *data, const char *field, size_t flen, const char *value, size_t vlen);

typedef struct http_parser { 
  int cs;
  const char *body_start;
  int content_len;
  size_t nread;
  const char *mark;
  const char *field_start;
  size_t field_len;

  void *data;

  field_cb http_field;
  element_cb request_method;
  element_cb request_uri;
  element_cb query_string;
  element_cb http_version;
  element_cb header_done;
  
} http_parser;

int http_parser_init(http_parser *parser);
int http_parser_finish(http_parser *parser);
size_t http_parser_execute(http_parser *parser, const char *data, size_t len );
int http_parser_has_error(http_parser *parser);
int http_parser_is_finished(http_parser *parser);
void http_parser_destroy(http_parser *parser);

#define http_parser_nread(parser) (parser)->nread 

#endif
