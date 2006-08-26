#line 1 "ext/http11/http11_parser.rl"
/**
 * Copyright (c) 2005 Zed A. Shaw
 * You can redistribute it and/or modify it under the same terms as Ruby.
 */
#include "http11_parser.h"
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define LEN(AT, FPC) (FPC - buffer - parser->AT)
#define MARK(M,FPC) (parser->M = (FPC) - buffer)
#define PTR_TO(F) (buffer + parser->F)

/** machine **/
#line 114 "ext/http11/http11_parser.rl"


/** Data **/

#line 24 "ext/http11/http11_parser.c"
static const int http_parser_start = 0;

static const int http_parser_first_final = 53;

static const int http_parser_error = 1;

#line 118 "ext/http11/http11_parser.rl"

int http_parser_init(http_parser *parser)  {
  int cs = 0;
  
#line 36 "ext/http11/http11_parser.c"
	{
	cs = http_parser_start;
	}
#line 122 "ext/http11/http11_parser.rl"
  parser->cs = cs;
  parser->body_start = 0;
  parser->content_len = 0;
  parser->mark = 0;
  parser->nread = 0;
  parser->field_len = 0;
  parser->field_start = 0;    

  return(1);
}


/** exec **/
size_t http_parser_execute(http_parser *parser, const char *buffer, size_t len, size_t off)  {
  const char *p, *pe;
  int cs = parser->cs;

  assert(off <= len && "offset past end of buffer");

  p = buffer+off;
  pe = buffer+len;

  assert(*pe == '\0' && "pointer does not end on NUL");
  assert(pe - p == len - off && "pointers aren't same distance");


  
#line 68 "ext/http11/http11_parser.c"
	{
	if ( p == pe )
		goto _out;
	switch ( cs )
	{
case 0:
	switch( (*p) ) {
		case 36: goto tr14;
		case 95: goto tr14;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto tr14;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto tr14;
	} else
		goto tr14;
	goto st1;
st1:
	goto _out1;
tr14:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st2;
st2:
	if ( ++p == pe )
		goto _out2;
case 2:
#line 98 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st34;
		case 95: goto st34;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st34;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st34;
	} else
		goto st34;
	goto st1;
tr17:
#line 34 "ext/http11/http11_parser.rl"
	{ 
    if(parser->request_method != NULL) 
      parser->request_method(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st3;
st3:
	if ( ++p == pe )
		goto _out3;
case 3:
#line 124 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 42: goto tr10;
		case 43: goto tr11;
		case 47: goto tr12;
		case 58: goto tr13;
	}
	if ( (*p) < 65 ) {
		if ( 45 <= (*p) && (*p) <= 57 )
			goto tr11;
	} else if ( (*p) > 90 ) {
		if ( 97 <= (*p) && (*p) <= 122 )
			goto tr11;
	} else
		goto tr11;
	goto st1;
tr10:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st4;
st4:
	if ( ++p == pe )
		goto _out4;
case 4:
#line 148 "ext/http11/http11_parser.c"
	if ( (*p) == 32 )
		goto tr19;
	goto st1;
tr19:
#line 38 "ext/http11/http11_parser.rl"
	{ 
    if(parser->request_uri != NULL)
      parser->request_uri(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st5;
tr28:
#line 44 "ext/http11/http11_parser.rl"
	{ 
    if(parser->query_string != NULL)
      parser->query_string(parser->data, PTR_TO(query_start), LEN(query_start, p));
  }
#line 38 "ext/http11/http11_parser.rl"
	{ 
    if(parser->request_uri != NULL)
      parser->request_uri(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st5;
tr31:
#line 54 "ext/http11/http11_parser.rl"
	{
    if(parser->request_path != NULL)
      parser->request_path(parser->data, PTR_TO(mark), LEN(mark,p));
  }
#line 38 "ext/http11/http11_parser.rl"
	{ 
    if(parser->request_uri != NULL)
      parser->request_uri(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st5;
tr40:
#line 43 "ext/http11/http11_parser.rl"
	{MARK(query_start, p); }
#line 44 "ext/http11/http11_parser.rl"
	{ 
    if(parser->query_string != NULL)
      parser->query_string(parser->data, PTR_TO(query_start), LEN(query_start, p));
  }
#line 38 "ext/http11/http11_parser.rl"
	{ 
    if(parser->request_uri != NULL)
      parser->request_uri(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st5;
st5:
	if ( ++p == pe )
		goto _out5;
case 5:
#line 201 "ext/http11/http11_parser.c"
	if ( (*p) == 72 )
		goto tr3;
	goto st1;
tr3:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st6;
st6:
	if ( ++p == pe )
		goto _out6;
case 6:
#line 213 "ext/http11/http11_parser.c"
	if ( (*p) == 84 )
		goto st7;
	goto st1;
st7:
	if ( ++p == pe )
		goto _out7;
case 7:
	if ( (*p) == 84 )
		goto st8;
	goto st1;
st8:
	if ( ++p == pe )
		goto _out8;
case 8:
	if ( (*p) == 80 )
		goto st9;
	goto st1;
st9:
	if ( ++p == pe )
		goto _out9;
case 9:
	if ( (*p) == 47 )
		goto st10;
	goto st1;
st10:
	if ( ++p == pe )
		goto _out10;
case 10:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st11;
	goto st1;
st11:
	if ( ++p == pe )
		goto _out11;
case 11:
	if ( (*p) == 46 )
		goto st12;
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st11;
	goto st1;
st12:
	if ( ++p == pe )
		goto _out12;
case 12:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st13;
	goto st1;
st13:
	if ( ++p == pe )
		goto _out13;
case 13:
	if ( (*p) == 13 )
		goto tr22;
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st13;
	goto st1;
tr22:
#line 49 "ext/http11/http11_parser.rl"
	{	
    if(parser->http_version != NULL)
      parser->http_version(parser->data, PTR_TO(mark), LEN(mark, p));
  }
	goto st14;
tr36:
#line 29 "ext/http11/http11_parser.rl"
	{ 
    if(parser->http_field != NULL) {
      parser->http_field(parser->data, PTR_TO(field_start), parser->field_len, PTR_TO(mark), LEN(mark, p));
    }
  }
	goto st14;
st14:
	if ( ++p == pe )
		goto _out14;
case 14:
#line 289 "ext/http11/http11_parser.c"
	if ( (*p) == 10 )
		goto st15;
	goto st1;
st15:
	if ( ++p == pe )
		goto _out15;
case 15:
	switch( (*p) ) {
		case 13: goto st16;
		case 33: goto tr21;
		case 124: goto tr21;
		case 126: goto tr21;
	}
	if ( (*p) < 45 ) {
		if ( (*p) > 39 ) {
			if ( 42 <= (*p) && (*p) <= 43 )
				goto tr21;
		} else if ( (*p) >= 35 )
			goto tr21;
	} else if ( (*p) > 46 ) {
		if ( (*p) < 65 ) {
			if ( 48 <= (*p) && (*p) <= 57 )
				goto tr21;
		} else if ( (*p) > 90 ) {
			if ( 94 <= (*p) && (*p) <= 122 )
				goto tr21;
		} else
			goto tr21;
	} else
		goto tr21;
	goto st1;
st16:
	if ( ++p == pe )
		goto _out16;
case 16:
	if ( (*p) == 10 )
		goto tr25;
	goto st1;
tr25:
#line 59 "ext/http11/http11_parser.rl"
	{ 
    parser->body_start = p - buffer + 1; 
    if(parser->header_done != NULL)
      parser->header_done(parser->data, p + 1, pe - p - 1);
    goto _out53;
  }
	goto st53;
st53:
	if ( ++p == pe )
		goto _out53;
case 53:
#line 341 "ext/http11/http11_parser.c"
	goto st1;
tr21:
#line 23 "ext/http11/http11_parser.rl"
	{ MARK(field_start, p); }
	goto st17;
st17:
	if ( ++p == pe )
		goto _out17;
case 17:
#line 351 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 33: goto st17;
		case 58: goto tr16;
		case 124: goto st17;
		case 126: goto st17;
	}
	if ( (*p) < 45 ) {
		if ( (*p) > 39 ) {
			if ( 42 <= (*p) && (*p) <= 43 )
				goto st17;
		} else if ( (*p) >= 35 )
			goto st17;
	} else if ( (*p) > 46 ) {
		if ( (*p) < 65 ) {
			if ( 48 <= (*p) && (*p) <= 57 )
				goto st17;
		} else if ( (*p) > 90 ) {
			if ( 94 <= (*p) && (*p) <= 122 )
				goto st17;
		} else
			goto st17;
	} else
		goto st17;
	goto st1;
tr16:
#line 24 "ext/http11/http11_parser.rl"
	{ 
    parser->field_len = LEN(field_start, p);
  }
	goto st18;
tr38:
#line 28 "ext/http11/http11_parser.rl"
	{ MARK(mark, p); }
	goto st18;
st18:
	if ( ++p == pe )
		goto _out18;
case 18:
#line 390 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 13: goto tr36;
		case 32: goto tr38;
	}
	goto tr37;
tr37:
#line 28 "ext/http11/http11_parser.rl"
	{ MARK(mark, p); }
	goto st19;
st19:
	if ( ++p == pe )
		goto _out19;
case 19:
#line 404 "ext/http11/http11_parser.c"
	if ( (*p) == 13 )
		goto tr36;
	goto st19;
tr11:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st20;
st20:
	if ( ++p == pe )
		goto _out20;
case 20:
#line 416 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 43: goto st20;
		case 58: goto st21;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st20;
	} else if ( (*p) > 57 ) {
		if ( (*p) > 90 ) {
			if ( 97 <= (*p) && (*p) <= 122 )
				goto st20;
		} else if ( (*p) >= 65 )
			goto st20;
	} else
		goto st20;
	goto st1;
tr13:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st21;
st21:
	if ( ++p == pe )
		goto _out21;
case 21:
#line 441 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr19;
		case 37: goto st22;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st21;
st22:
	if ( ++p == pe )
		goto _out22;
case 22:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st23;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st23;
	} else
		goto st23;
	goto st1;
st23:
	if ( ++p == pe )
		goto _out23;
case 23:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st21;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st21;
	} else
		goto st21;
	goto st1;
tr12:
#line 20 "ext/http11/http11_parser.rl"
	{MARK(mark, p); }
	goto st24;
st24:
	if ( ++p == pe )
		goto _out24;
case 24:
#line 489 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr31;
		case 37: goto st25;
		case 59: goto tr33;
		case 60: goto st1;
		case 62: goto st1;
		case 63: goto tr34;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st24;
st25:
	if ( ++p == pe )
		goto _out25;
case 25:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st26;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st26;
	} else
		goto st26;
	goto st1;
st26:
	if ( ++p == pe )
		goto _out26;
case 26:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st24;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st24;
	} else
		goto st24;
	goto st1;
tr33:
#line 54 "ext/http11/http11_parser.rl"
	{
    if(parser->request_path != NULL)
      parser->request_path(parser->data, PTR_TO(mark), LEN(mark,p));
  }
	goto st27;
st27:
	if ( ++p == pe )
		goto _out27;
case 27:
#line 542 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr19;
		case 37: goto st28;
		case 60: goto st1;
		case 62: goto st1;
		case 63: goto st30;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st27;
st28:
	if ( ++p == pe )
		goto _out28;
case 28:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st29;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st29;
	} else
		goto st29;
	goto st1;
st29:
	if ( ++p == pe )
		goto _out29;
case 29:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st27;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st27;
	} else
		goto st27;
	goto st1;
tr34:
#line 54 "ext/http11/http11_parser.rl"
	{
    if(parser->request_path != NULL)
      parser->request_path(parser->data, PTR_TO(mark), LEN(mark,p));
  }
	goto st30;
st30:
	if ( ++p == pe )
		goto _out30;
case 30:
#line 594 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr40;
		case 37: goto tr41;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto tr39;
tr39:
#line 43 "ext/http11/http11_parser.rl"
	{MARK(query_start, p); }
	goto st31;
st31:
	if ( ++p == pe )
		goto _out31;
case 31:
#line 616 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr28;
		case 37: goto st32;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st31;
tr41:
#line 43 "ext/http11/http11_parser.rl"
	{MARK(query_start, p); }
	goto st32;
st32:
	if ( ++p == pe )
		goto _out32;
case 32:
#line 638 "ext/http11/http11_parser.c"
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st33;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st33;
	} else
		goto st33;
	goto st1;
st33:
	if ( ++p == pe )
		goto _out33;
case 33:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st31;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st31;
	} else
		goto st31;
	goto st1;
st34:
	if ( ++p == pe )
		goto _out34;
case 34:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st35;
		case 95: goto st35;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st35;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st35;
	} else
		goto st35;
	goto st1;
st35:
	if ( ++p == pe )
		goto _out35;
case 35:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st36;
		case 95: goto st36;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st36;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st36;
	} else
		goto st36;
	goto st1;
st36:
	if ( ++p == pe )
		goto _out36;
case 36:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st37;
		case 95: goto st37;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st37;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st37;
	} else
		goto st37;
	goto st1;
st37:
	if ( ++p == pe )
		goto _out37;
case 37:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st38;
		case 95: goto st38;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st38;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st38;
	} else
		goto st38;
	goto st1;
st38:
	if ( ++p == pe )
		goto _out38;
case 38:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st39;
		case 95: goto st39;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st39;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st39;
	} else
		goto st39;
	goto st1;
st39:
	if ( ++p == pe )
		goto _out39;
case 39:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st40;
		case 95: goto st40;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st40;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st40;
	} else
		goto st40;
	goto st1;
st40:
	if ( ++p == pe )
		goto _out40;
case 40:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st41;
		case 95: goto st41;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st41;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st41;
	} else
		goto st41;
	goto st1;
st41:
	if ( ++p == pe )
		goto _out41;
case 41:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st42;
		case 95: goto st42;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st42;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st42;
	} else
		goto st42;
	goto st1;
st42:
	if ( ++p == pe )
		goto _out42;
case 42:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st43;
		case 95: goto st43;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st43;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st43;
	} else
		goto st43;
	goto st1;
st43:
	if ( ++p == pe )
		goto _out43;
case 43:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st44;
		case 95: goto st44;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st44;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st44;
	} else
		goto st44;
	goto st1;
st44:
	if ( ++p == pe )
		goto _out44;
case 44:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st45;
		case 95: goto st45;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st45;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st45;
	} else
		goto st45;
	goto st1;
st45:
	if ( ++p == pe )
		goto _out45;
case 45:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st46;
		case 95: goto st46;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st46;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st46;
	} else
		goto st46;
	goto st1;
st46:
	if ( ++p == pe )
		goto _out46;
case 46:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st47;
		case 95: goto st47;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st47;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st47;
	} else
		goto st47;
	goto st1;
st47:
	if ( ++p == pe )
		goto _out47;
case 47:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st48;
		case 95: goto st48;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st48;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st48;
	} else
		goto st48;
	goto st1;
st48:
	if ( ++p == pe )
		goto _out48;
case 48:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st49;
		case 95: goto st49;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st49;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st49;
	} else
		goto st49;
	goto st1;
st49:
	if ( ++p == pe )
		goto _out49;
case 49:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st50;
		case 95: goto st50;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st50;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st50;
	} else
		goto st50;
	goto st1;
st50:
	if ( ++p == pe )
		goto _out50;
case 50:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st51;
		case 95: goto st51;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st51;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st51;
	} else
		goto st51;
	goto st1;
st51:
	if ( ++p == pe )
		goto _out51;
case 51:
	switch( (*p) ) {
		case 32: goto tr17;
		case 36: goto st52;
		case 95: goto st52;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st52;
	} else if ( (*p) > 57 ) {
		if ( 65 <= (*p) && (*p) <= 90 )
			goto st52;
	} else
		goto st52;
	goto st1;
st52:
	if ( ++p == pe )
		goto _out52;
case 52:
	if ( (*p) == 32 )
		goto tr17;
	goto st1;
	}
	_out1: cs = 1; goto _out; 
	_out2: cs = 2; goto _out; 
	_out3: cs = 3; goto _out; 
	_out4: cs = 4; goto _out; 
	_out5: cs = 5; goto _out; 
	_out6: cs = 6; goto _out; 
	_out7: cs = 7; goto _out; 
	_out8: cs = 8; goto _out; 
	_out9: cs = 9; goto _out; 
	_out10: cs = 10; goto _out; 
	_out11: cs = 11; goto _out; 
	_out12: cs = 12; goto _out; 
	_out13: cs = 13; goto _out; 
	_out14: cs = 14; goto _out; 
	_out15: cs = 15; goto _out; 
	_out16: cs = 16; goto _out; 
	_out53: cs = 53; goto _out; 
	_out17: cs = 17; goto _out; 
	_out18: cs = 18; goto _out; 
	_out19: cs = 19; goto _out; 
	_out20: cs = 20; goto _out; 
	_out21: cs = 21; goto _out; 
	_out22: cs = 22; goto _out; 
	_out23: cs = 23; goto _out; 
	_out24: cs = 24; goto _out; 
	_out25: cs = 25; goto _out; 
	_out26: cs = 26; goto _out; 
	_out27: cs = 27; goto _out; 
	_out28: cs = 28; goto _out; 
	_out29: cs = 29; goto _out; 
	_out30: cs = 30; goto _out; 
	_out31: cs = 31; goto _out; 
	_out32: cs = 32; goto _out; 
	_out33: cs = 33; goto _out; 
	_out34: cs = 34; goto _out; 
	_out35: cs = 35; goto _out; 
	_out36: cs = 36; goto _out; 
	_out37: cs = 37; goto _out; 
	_out38: cs = 38; goto _out; 
	_out39: cs = 39; goto _out; 
	_out40: cs = 40; goto _out; 
	_out41: cs = 41; goto _out; 
	_out42: cs = 42; goto _out; 
	_out43: cs = 43; goto _out; 
	_out44: cs = 44; goto _out; 
	_out45: cs = 45; goto _out; 
	_out46: cs = 46; goto _out; 
	_out47: cs = 47; goto _out; 
	_out48: cs = 48; goto _out; 
	_out49: cs = 49; goto _out; 
	_out50: cs = 50; goto _out; 
	_out51: cs = 51; goto _out; 
	_out52: cs = 52; goto _out; 

	_out: {}
	}
#line 149 "ext/http11/http11_parser.rl"

  parser->cs = cs;
  parser->nread += p - (buffer + off);

  assert(p <= pe && "buffer overflow after parsing execute");
  assert(parser->nread <= len && "nread longer than length");
  assert(parser->body_start <= len && "body starts after buffer end");
  assert(parser->mark < len && "mark is after buffer end");
  assert(parser->field_len <= len && "field has length longer than whole buffer");
  assert(parser->field_start < len && "field starts after buffer end");

  if(parser->body_start) {
    /* final \r\n combo encountered so stop right here */
    
#line 1064 "ext/http11/http11_parser.c"
#line 163 "ext/http11/http11_parser.rl"
    parser->nread++;
  }

  return(parser->nread);
}

int http_parser_finish(http_parser *parser)
{
  int cs = parser->cs;

  
#line 1077 "ext/http11/http11_parser.c"
#line 174 "ext/http11/http11_parser.rl"

  parser->cs = cs;

  if (http_parser_has_error(parser) ) {
    return -1;
  } else if (http_parser_is_finished(parser) ) {
    return 1;
  } else {
    return 0;
  }
}

int http_parser_has_error(http_parser *parser) {
  return parser->cs == http_parser_error;
}

int http_parser_is_finished(http_parser *parser) {
  return parser->cs == http_parser_first_final;
}
