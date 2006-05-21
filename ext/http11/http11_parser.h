/* Mongrel Web Server - A Mostly Ruby Webserver and Library
 *
 * Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

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
  size_t body_start;
  int content_len;
  size_t nread;
  size_t mark;
  size_t field_start;
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
size_t http_parser_execute(http_parser *parser, const char *data, size_t len, size_t off);
int http_parser_has_error(http_parser *parser);
int http_parser_is_finished(http_parser *parser);

#define http_parser_nread(parser) (parser)->nread 

#endif
