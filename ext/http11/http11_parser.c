#line 1 "ext/http11/http11_parser.rl"
#include "http11_parser.h"
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define MARK(S,F) assert((F) - (S)->mark >= 0); (S)->mark = (F);

/** machine **/
#line 98 "ext/http11/http11_parser.rl"


/** Data **/

#line 18 "ext/http11/http11_parser.c"
static int http_parser_start = 0;

static int http_parser_first_final = 53;

static int http_parser_error = 1;

#line 102 "ext/http11/http11_parser.rl"

int http_parser_init(http_parser *parser)  {
    int cs = 0;
    
#line 30 "ext/http11/http11_parser.c"
	{
	cs = http_parser_start;
	}
#line 106 "ext/http11/http11_parser.rl"
    parser->cs = cs;
    parser->body_start = NULL;
    parser->content_len = 0;
    parser->mark = NULL;
    parser->nread = 0;

    return(1);
}


/** exec **/
size_t http_parser_execute(http_parser *parser, const char *buffer, size_t len)  {
    const char *p, *pe;
    int cs = parser->cs;

    p = buffer;
    pe = buffer+len;

    
#line 54 "ext/http11/http11_parser.c"
	{
	p -= 1;
	if ( ++p == pe )
		goto _out;
	switch ( cs )
	{
case 0:
	switch( (*p) ) {
		case 68: goto tr13;
		case 71: goto tr14;
		case 72: goto tr15;
		case 79: goto tr16;
		case 80: goto tr17;
		case 84: goto tr18;
	}
	goto st1;
st1:
	goto _out1;
tr13:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st2;
st2:
	if ( ++p == pe )
		goto _out2;
case 2:
#line 81 "ext/http11/http11_parser.c"
	if ( (*p) == 69 )
		goto st3;
	goto st1;
st3:
	if ( ++p == pe )
		goto _out3;
case 3:
	if ( (*p) == 76 )
		goto st4;
	goto st1;
st4:
	if ( ++p == pe )
		goto _out4;
case 4:
	if ( (*p) == 69 )
		goto st5;
	goto st1;
st5:
	if ( ++p == pe )
		goto _out5;
case 5:
	if ( (*p) == 84 )
		goto st6;
	goto st1;
st6:
	if ( ++p == pe )
		goto _out6;
case 6:
	if ( (*p) == 69 )
		goto st7;
	goto st1;
st7:
	if ( ++p == pe )
		goto _out7;
case 7:
	if ( (*p) == 32 )
		goto tr33;
	goto st1;
tr33:
#line 29 "ext/http11/http11_parser.rl"
	{ 
	       if(parser->request_method != NULL)
	       	       parser->request_method(parser->data, parser->mark, p - parser->mark);
	}
	goto st8;
st8:
	if ( ++p == pe )
		goto _out8;
case 8:
#line 131 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 42: goto tr27;
		case 43: goto tr28;
		case 47: goto tr29;
		case 58: goto tr30;
	}
	if ( (*p) < 65 ) {
		if ( 45 <= (*p) && (*p) <= 57 )
			goto tr28;
	} else if ( (*p) > 90 ) {
		if ( 97 <= (*p) && (*p) <= 122 )
			goto tr28;
	} else
		goto tr28;
	goto st1;
tr27:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st9;
st9:
	if ( ++p == pe )
		goto _out9;
case 9:
#line 155 "ext/http11/http11_parser.c"
	if ( (*p) == 32 )
		goto tr34;
	goto st1;
tr34:
#line 33 "ext/http11/http11_parser.rl"
	{ 
	       if(parser->request_uri != NULL)
	       	       parser->request_uri(parser->data, parser->mark, p - parser->mark);
	}
	goto st10;
tr46:
#line 37 "ext/http11/http11_parser.rl"
	{ 
	       if(parser->query_string != NULL)
	       	       parser->query_string(parser->data, parser->mark, p - parser->mark);
	}
	goto st10;
st10:
	if ( ++p == pe )
		goto _out10;
case 10:
#line 177 "ext/http11/http11_parser.c"
	if ( (*p) == 72 )
		goto tr11;
	goto st1;
tr11:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st11;
st11:
	if ( ++p == pe )
		goto _out11;
case 11:
#line 189 "ext/http11/http11_parser.c"
	if ( (*p) == 84 )
		goto st12;
	goto st1;
st12:
	if ( ++p == pe )
		goto _out12;
case 12:
	if ( (*p) == 84 )
		goto st13;
	goto st1;
st13:
	if ( ++p == pe )
		goto _out13;
case 13:
	if ( (*p) == 80 )
		goto st14;
	goto st1;
st14:
	if ( ++p == pe )
		goto _out14;
case 14:
	if ( (*p) == 47 )
		goto st15;
	goto st1;
st15:
	if ( ++p == pe )
		goto _out15;
case 15:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st16;
	goto st1;
st16:
	if ( ++p == pe )
		goto _out16;
case 16:
	if ( (*p) == 46 )
		goto st17;
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st16;
	goto st1;
st17:
	if ( ++p == pe )
		goto _out17;
case 17:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st18;
	goto st1;
st18:
	if ( ++p == pe )
		goto _out18;
case 18:
	if ( (*p) == 13 )
		goto tr37;
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st18;
	goto st1;
tr37:
#line 42 "ext/http11/http11_parser.rl"
	{	
	       if(parser->http_version != NULL)
	       	       parser->http_version(parser->data, parser->mark, p - parser->mark);
	}
	goto st19;
tr49:
#line 22 "ext/http11/http11_parser.rl"
	{ 
	       if(parser->http_field != NULL) {
	       	       parser->http_field(parser->data, 
		       		parser->field_start, parser->field_len, 
				parser->mark+1, p - (parser->mark +1));
		}
	}
	goto st19;
st19:
	if ( ++p == pe )
		goto _out19;
case 19:
#line 267 "ext/http11/http11_parser.c"
	if ( (*p) == 10 )
		goto st20;
	goto st1;
st20:
	if ( ++p == pe )
		goto _out20;
case 20:
	switch( (*p) ) {
		case 13: goto st21;
		case 33: goto tr36;
		case 124: goto tr36;
		case 126: goto tr36;
	}
	if ( (*p) < 45 ) {
		if ( (*p) > 39 ) {
			if ( 42 <= (*p) && (*p) <= 43 )
				goto tr36;
		} else if ( (*p) >= 35 )
			goto tr36;
	} else if ( (*p) > 46 ) {
		if ( (*p) < 65 ) {
			if ( 48 <= (*p) && (*p) <= 57 )
				goto tr36;
		} else if ( (*p) > 90 ) {
			if ( 94 <= (*p) && (*p) <= 122 )
				goto tr36;
		} else
			goto tr36;
	} else
		goto tr36;
	goto st1;
st21:
	if ( ++p == pe )
		goto _out21;
case 21:
	if ( (*p) == 10 )
		goto tr40;
	goto st1;
tr40:
#line 46 "ext/http11/http11_parser.rl"
	{ 
	       parser->body_start = p+1; goto _out53;
	}
	goto st53;
st53:
	if ( ++p == pe )
		goto _out53;
case 53:
#line 316 "ext/http11/http11_parser.c"
	goto st1;
tr36:
#line 16 "ext/http11/http11_parser.rl"
	{ parser->field_start = p; }
	goto st22;
st22:
	if ( ++p == pe )
		goto _out22;
case 22:
#line 326 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 33: goto st22;
		case 58: goto tr32;
		case 124: goto st22;
		case 126: goto st22;
	}
	if ( (*p) < 45 ) {
		if ( (*p) > 39 ) {
			if ( 42 <= (*p) && (*p) <= 43 )
				goto st22;
		} else if ( (*p) >= 35 )
			goto st22;
	} else if ( (*p) > 46 ) {
		if ( (*p) < 65 ) {
			if ( 48 <= (*p) && (*p) <= 57 )
				goto st22;
		} else if ( (*p) > 90 ) {
			if ( 94 <= (*p) && (*p) <= 122 )
				goto st22;
		} else
			goto st22;
	} else
		goto st22;
	goto st1;
tr32:
#line 17 "ext/http11/http11_parser.rl"
	{ 
	       parser->field_len = (p - parser->field_start);
	}
	goto st23;
st23:
	if ( ++p == pe )
		goto _out23;
case 23:
#line 361 "ext/http11/http11_parser.c"
	if ( (*p) == 13 )
		goto tr49;
	goto tr52;
tr52:
#line 21 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st24;
st24:
	if ( ++p == pe )
		goto _out24;
case 24:
#line 373 "ext/http11/http11_parser.c"
	if ( (*p) == 13 )
		goto tr49;
	goto st24;
tr28:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st25;
st25:
	if ( ++p == pe )
		goto _out25;
case 25:
#line 385 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 43: goto st25;
		case 58: goto st26;
	}
	if ( (*p) < 48 ) {
		if ( 45 <= (*p) && (*p) <= 46 )
			goto st25;
	} else if ( (*p) > 57 ) {
		if ( (*p) > 90 ) {
			if ( 97 <= (*p) && (*p) <= 122 )
				goto st25;
		} else if ( (*p) >= 65 )
			goto st25;
	} else
		goto st25;
	goto st1;
tr30:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st26;
st26:
	if ( ++p == pe )
		goto _out26;
case 26:
#line 410 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr34;
		case 37: goto st27;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st26;
st27:
	if ( ++p == pe )
		goto _out27;
case 27:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st28;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st28;
	} else
		goto st28;
	goto st1;
st28:
	if ( ++p == pe )
		goto _out28;
case 28:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st26;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st26;
	} else
		goto st26;
	goto st1;
tr29:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st29;
st29:
	if ( ++p == pe )
		goto _out29;
case 29:
#line 458 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr34;
		case 37: goto st31;
		case 47: goto st1;
		case 60: goto st1;
		case 62: goto st1;
		case 63: goto tr44;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st30;
st30:
	if ( ++p == pe )
		goto _out30;
case 30:
	switch( (*p) ) {
		case 32: goto tr34;
		case 37: goto st31;
		case 60: goto st1;
		case 62: goto st1;
		case 63: goto tr44;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st30;
st31:
	if ( ++p == pe )
		goto _out31;
case 31:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st32;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st32;
	} else
		goto st32;
	goto st1;
st32:
	if ( ++p == pe )
		goto _out32;
case 32:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st30;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st30;
	} else
		goto st30;
	goto st1;
tr44:
#line 33 "ext/http11/http11_parser.rl"
	{ 
	       if(parser->request_uri != NULL)
	       	       parser->request_uri(parser->data, parser->mark, p - parser->mark);
	}
	goto st33;
st33:
	if ( ++p == pe )
		goto _out33;
case 33:
#line 529 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr46;
		case 37: goto tr51;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto tr50;
tr50:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st34;
st34:
	if ( ++p == pe )
		goto _out34;
case 34:
#line 551 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 32: goto tr46;
		case 37: goto st35;
		case 60: goto st1;
		case 62: goto st1;
		case 127: goto st1;
	}
	if ( (*p) > 31 ) {
		if ( 34 <= (*p) && (*p) <= 35 )
			goto st1;
	} else if ( (*p) >= 0 )
		goto st1;
	goto st34;
tr51:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st35;
st35:
	if ( ++p == pe )
		goto _out35;
case 35:
#line 573 "ext/http11/http11_parser.c"
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st36;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st36;
	} else
		goto st36;
	goto st1;
st36:
	if ( ++p == pe )
		goto _out36;
case 36:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st34;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st34;
	} else
		goto st34;
	goto st1;
tr14:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st37;
st37:
	if ( ++p == pe )
		goto _out37;
case 37:
#line 604 "ext/http11/http11_parser.c"
	if ( (*p) == 69 )
		goto st38;
	goto st1;
st38:
	if ( ++p == pe )
		goto _out38;
case 38:
	if ( (*p) == 84 )
		goto st7;
	goto st1;
tr15:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st39;
st39:
	if ( ++p == pe )
		goto _out39;
case 39:
#line 623 "ext/http11/http11_parser.c"
	if ( (*p) == 69 )
		goto st40;
	goto st1;
st40:
	if ( ++p == pe )
		goto _out40;
case 40:
	if ( (*p) == 65 )
		goto st41;
	goto st1;
st41:
	if ( ++p == pe )
		goto _out41;
case 41:
	if ( (*p) == 68 )
		goto st7;
	goto st1;
tr16:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st42;
st42:
	if ( ++p == pe )
		goto _out42;
case 42:
#line 649 "ext/http11/http11_parser.c"
	if ( (*p) == 80 )
		goto st43;
	goto st1;
st43:
	if ( ++p == pe )
		goto _out43;
case 43:
	if ( (*p) == 84 )
		goto st44;
	goto st1;
st44:
	if ( ++p == pe )
		goto _out44;
case 44:
	if ( (*p) == 73 )
		goto st45;
	goto st1;
st45:
	if ( ++p == pe )
		goto _out45;
case 45:
	if ( (*p) == 79 )
		goto st46;
	goto st1;
st46:
	if ( ++p == pe )
		goto _out46;
case 46:
	if ( (*p) == 78 )
		goto st47;
	goto st1;
st47:
	if ( ++p == pe )
		goto _out47;
case 47:
	if ( (*p) == 83 )
		goto st7;
	goto st1;
tr17:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st48;
st48:
	if ( ++p == pe )
		goto _out48;
case 48:
#line 696 "ext/http11/http11_parser.c"
	switch( (*p) ) {
		case 79: goto st49;
		case 85: goto st38;
	}
	goto st1;
st49:
	if ( ++p == pe )
		goto _out49;
case 49:
	if ( (*p) == 83 )
		goto st38;
	goto st1;
tr18:
#line 14 "ext/http11/http11_parser.rl"
	{ MARK(parser, p); }
	goto st50;
st50:
	if ( ++p == pe )
		goto _out50;
case 50:
#line 717 "ext/http11/http11_parser.c"
	if ( (*p) == 82 )
		goto st51;
	goto st1;
st51:
	if ( ++p == pe )
		goto _out51;
case 51:
	if ( (*p) == 65 )
		goto st52;
	goto st1;
st52:
	if ( ++p == pe )
		goto _out52;
case 52:
	if ( (*p) == 67 )
		goto st6;
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
	_out17: cs = 17; goto _out; 
	_out18: cs = 18; goto _out; 
	_out19: cs = 19; goto _out; 
	_out20: cs = 20; goto _out; 
	_out21: cs = 21; goto _out; 
	_out53: cs = 53; goto _out; 
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
#line 125 "ext/http11/http11_parser.rl"

    parser->cs = cs;
    parser->nread = p - buffer;
    if(parser->body_start) {
        /* final \r\n combo encountered so stop right here */
	
#line 799 "ext/http11/http11_parser.c"
#line 131 "ext/http11/http11_parser.rl"
	parser->nread++;
    }

    return(parser->nread);
}

int http_parser_finish(http_parser *parser)
{
	int cs = parser->cs;

	
#line 812 "ext/http11/http11_parser.c"
#line 142 "ext/http11/http11_parser.rl"

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
