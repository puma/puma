
// line 1 "ext/puma_http11/http11_parser.java.rl"
package org.jruby.puma;

import org.jruby.Ruby;
import org.jruby.RubyHash;
import org.jruby.util.ByteList;

public class Http11Parser {

/** Machine **/


// line 58 "ext/puma_http11/http11_parser.java.rl"


/** Data **/

// line 20 "ext/puma_http11/org/jruby/puma/Http11Parser.java"
private static byte[] init__puma_parser_actions_0()
{
	return new byte [] {
	    0,    1,    0,    1,    2,    1,    3,    1,    4,    1,    5,    1,
	    6,    1,    7,    1,    8,    1,    9,    1,   11,    1,   12,    1,
	   13,    2,    0,    8,    2,    1,    2,    2,    4,    5,    2,   10,
	    7,    2,   12,    7,    3,    9,   10,    7
	};
}

private static final byte _puma_parser_actions[] = init__puma_parser_actions_0();


private static short[] init__puma_parser_key_offsets_0()
{
	return new short [] {
	    0,    0,    8,   17,   27,   29,   30,   31,   32,   33,   34,   36,
	   39,   41,   44,   45,   61,   62,   78,   85,   91,   99,  107,  117,
	  125,  134,  142,  150,  159,  168,  177,  186,  195,  204,  213,  222,
	  231,  240,  249,  258,  267,  276,  285,  294,  303,  312,  313
	};
}

private static final short _puma_parser_key_offsets[] = init__puma_parser_key_offsets_0();


private static char[] init__puma_parser_trans_keys_0()
{
	return new char [] {
	   36,   95,   45,   46,   48,   57,   65,   90,   32,   36,   95,   45,
	   46,   48,   57,   65,   90,   42,   43,   47,   58,   45,   57,   65,
	   90,   97,  122,   32,   35,   72,   84,   84,   80,   47,   48,   57,
	   46,   48,   57,   48,   57,   13,   48,   57,   10,   13,   33,  124,
	  126,   35,   39,   42,   43,   45,   46,   48,   57,   65,   90,   94,
	  122,   10,   33,   58,  124,  126,   35,   39,   42,   43,   45,   46,
	   48,   57,   65,   90,   94,  122,   13,   32,  127,    0,    8,   10,
	   31,   13,  127,    0,    8,   10,   31,   32,   60,   62,  127,    0,
	   31,   34,   35,   32,   60,   62,  127,    0,   31,   34,   35,   43,
	   58,   45,   46,   48,   57,   65,   90,   97,  122,   32,   34,   35,
	   60,   62,  127,    0,   31,   32,   34,   35,   60,   62,   63,  127,
	    0,   31,   32,   34,   35,   60,   62,  127,    0,   31,   32,   34,
	   35,   60,   62,  127,    0,   31,   32,   36,   95,   45,   46,   48,
	   57,   65,   90,   32,   36,   95,   45,   46,   48,   57,   65,   90,
	   32,   36,   95,   45,   46,   48,   57,   65,   90,   32,   36,   95,
	   45,   46,   48,   57,   65,   90,   32,   36,   95,   45,   46,   48,
	   57,   65,   90,   32,   36,   95,   45,   46,   48,   57,   65,   90,
	   32,   36,   95,   45,   46,   48,   57,   65,   90,   32,   36,   95,
	   45,   46,   48,   57,   65,   90,   32,   36,   95,   45,   46,   48,
	   57,   65,   90,   32,   36,   95,   45,   46,   48,   57,   65,   90,
	   32,   36,   95,   45,   46,   48,   57,   65,   90,   32,   36,   95,
	   45,   46,   48,   57,   65,   90,   32,   36,   95,   45,   46,   48,
	   57,   65,   90,   32,   36,   95,   45,   46,   48,   57,   65,   90,
	   32,   36,   95,   45,   46,   48,   57,   65,   90,   32,   36,   95,
	   45,   46,   48,   57,   65,   90,   32,   36,   95,   45,   46,   48,
	   57,   65,   90,   32,   36,   95,   45,   46,   48,   57,   65,   90,
	   32,    0
	};
}

private static final char _puma_parser_trans_keys[] = init__puma_parser_trans_keys_0();


private static byte[] init__puma_parser_single_lengths_0()
{
	return new byte [] {
	    0,    2,    3,    4,    2,    1,    1,    1,    1,    1,    0,    1,
	    0,    1,    1,    4,    1,    4,    3,    2,    4,    4,    2,    6,
	    7,    6,    6,    3,    3,    3,    3,    3,    3,    3,    3,    3,
	    3,    3,    3,    3,    3,    3,    3,    3,    3,    1,    0
	};
}

private static final byte _puma_parser_single_lengths[] = init__puma_parser_single_lengths_0();


private static byte[] init__puma_parser_range_lengths_0()
{
	return new byte [] {
	    0,    3,    3,    3,    0,    0,    0,    0,    0,    0,    1,    1,
	    1,    1,    0,    6,    0,    6,    2,    2,    2,    2,    4,    1,
	    1,    1,    1,    3,    3,    3,    3,    3,    3,    3,    3,    3,
	    3,    3,    3,    3,    3,    3,    3,    3,    3,    0,    0
	};
}

private static final byte _puma_parser_range_lengths[] = init__puma_parser_range_lengths_0();


private static short[] init__puma_parser_index_offsets_0()
{
	return new short [] {
	    0,    0,    6,   13,   21,   24,   26,   28,   30,   32,   34,   36,
	   39,   41,   44,   46,   57,   59,   70,   76,   81,   88,   95,  102,
	  110,  119,  127,  135,  142,  149,  156,  163,  170,  177,  184,  191,
	  198,  205,  212,  219,  226,  233,  240,  247,  254,  261,  263
	};
}

private static final short _puma_parser_index_offsets[] = init__puma_parser_index_offsets_0();


private static byte[] init__puma_parser_indicies_0()
{
	return new byte [] {
	    0,    0,    0,    0,    0,    1,    2,    3,    3,    3,    3,    3,
	    1,    4,    5,    6,    7,    5,    5,    5,    1,    8,    9,    1,
	   10,    1,   11,    1,   12,    1,   13,    1,   14,    1,   15,    1,
	   16,   15,    1,   17,    1,   18,   17,    1,   19,    1,   20,   21,
	   21,   21,   21,   21,   21,   21,   21,   21,    1,   22,    1,   23,
	   24,   23,   23,   23,   23,   23,   23,   23,   23,    1,   26,   27,
	    1,    1,    1,   25,   29,    1,    1,    1,   28,   30,    1,    1,
	    1,    1,    1,   31,   32,    1,    1,    1,    1,    1,   33,   34,
	   35,   34,   34,   34,   34,    1,    8,    1,    9,    1,    1,    1,
	    1,   35,   36,    1,   38,    1,    1,   39,    1,    1,   37,   40,
	    1,   42,    1,    1,    1,    1,   41,   43,    1,   45,    1,    1,
	    1,    1,   44,    2,   46,   46,   46,   46,   46,    1,    2,   47,
	   47,   47,   47,   47,    1,    2,   48,   48,   48,   48,   48,    1,
	    2,   49,   49,   49,   49,   49,    1,    2,   50,   50,   50,   50,
	   50,    1,    2,   51,   51,   51,   51,   51,    1,    2,   52,   52,
	   52,   52,   52,    1,    2,   53,   53,   53,   53,   53,    1,    2,
	   54,   54,   54,   54,   54,    1,    2,   55,   55,   55,   55,   55,
	    1,    2,   56,   56,   56,   56,   56,    1,    2,   57,   57,   57,
	   57,   57,    1,    2,   58,   58,   58,   58,   58,    1,    2,   59,
	   59,   59,   59,   59,    1,    2,   60,   60,   60,   60,   60,    1,
	    2,   61,   61,   61,   61,   61,    1,    2,   62,   62,   62,   62,
	   62,    1,    2,   63,   63,   63,   63,   63,    1,    2,    1,    1,
	    0
	};
}

private static final byte _puma_parser_indicies[] = init__puma_parser_indicies_0();


private static byte[] init__puma_parser_trans_targs_0()
{
	return new byte [] {
	    2,    0,    3,   27,    4,   22,   24,   23,    5,   20,    6,    7,
	    8,    9,   10,   11,   12,   13,   14,   15,   16,   17,   46,   17,
	   18,   19,   14,   18,   19,   14,    5,   21,    5,   21,   22,   23,
	    5,   24,   20,   25,    5,   26,   20,    5,   26,   20,   28,   29,
	   30,   31,   32,   33,   34,   35,   36,   37,   38,   39,   40,   41,
	   42,   43,   44,   45
	};
}

private static final byte _puma_parser_trans_targs[] = init__puma_parser_trans_targs_0();


private static byte[] init__puma_parser_trans_actions_0()
{
	return new byte [] {
	    1,    0,   11,    0,    1,    1,    1,    1,   13,   13,    1,    0,
	    0,    0,    0,    0,    0,    0,   19,    0,    0,   28,   23,    3,
	    5,    7,   31,    7,    0,    9,   25,    1,   15,    0,    0,    0,
	   37,    0,   37,   21,   40,   17,   40,   34,    0,   34,    0,    0,
	    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
	    0,    0,    0,    0
	};
}

private static final byte _puma_parser_trans_actions[] = init__puma_parser_trans_actions_0();


static final int puma_parser_start = 1;
static final int puma_parser_first_final = 46;
static final int puma_parser_error = 0;


// line 62 "ext/puma_http11/http11_parser.java.rl"

   public static interface ElementCB {
     public void call(Ruby runtime, RubyHash data, ByteList buffer, int at, int length);
   }

   public static interface FieldCB {
     public void call(Ruby runtime, RubyHash data, ByteList buffer, int field, int flen, int value, int vlen);
   }

   public static class HttpParser {
      int cs;
      int body_start;
      int content_len;
      int nread;
      int mark;
      int field_start;
      int field_len;
      int query_start;

      RubyHash data;
      ByteList buffer;

      public void init() {
          cs = 0;

          
// line 216 "ext/puma_http11/org/jruby/puma/Http11Parser.java"
	{
	cs = puma_parser_start;
	}

// line 88 "ext/puma_http11/http11_parser.java.rl"

          body_start = 0;
          content_len = 0;
          mark = 0;
          nread = 0;
          field_len = 0;
          field_start = 0;
      }
   }

   public final HttpParser parser = new HttpParser();

   public int execute(Ruby runtime, Http11 http, ByteList buffer, int off) {
     int p, pe;
     int cs = parser.cs;
     int len = buffer.length();
     assert off<=len : "offset past end of buffer";

     p = off;
     pe = len;
     // get a copy of the bytes, since it may not start at 0
     // FIXME: figure out how to just use the bytes in-place
     byte[] data = buffer.bytes();
     parser.buffer = buffer;

     
// line 248 "ext/puma_http11/org/jruby/puma/Http11Parser.java"
	{
	int _klen;
	int _trans = 0;
	int _acts;
	int _nacts;
	int _keys;
	int _goto_targ = 0;

	_goto: while (true) {
	switch ( _goto_targ ) {
	case 0:
	if ( p == pe ) {
		_goto_targ = 4;
		continue _goto;
	}
	if ( cs == 0 ) {
		_goto_targ = 5;
		continue _goto;
	}
case 1:
	_match: do {
	_keys = _puma_parser_key_offsets[cs];
	_trans = _puma_parser_index_offsets[cs];
	_klen = _puma_parser_single_lengths[cs];
	if ( _klen > 0 ) {
		int _lower = _keys;
		int _mid;
		int _upper = _keys + _klen - 1;
		while (true) {
			if ( _upper < _lower )
				break;

			_mid = _lower + ((_upper-_lower) >> 1);
			if ( data[p] < _puma_parser_trans_keys[_mid] )
				_upper = _mid - 1;
			else if ( data[p] > _puma_parser_trans_keys[_mid] )
				_lower = _mid + 1;
			else {
				_trans += (_mid - _keys);
				break _match;
			}
		}
		_keys += _klen;
		_trans += _klen;
	}

	_klen = _puma_parser_range_lengths[cs];
	if ( _klen > 0 ) {
		int _lower = _keys;
		int _mid;
		int _upper = _keys + (_klen<<1) - 2;
		while (true) {
			if ( _upper < _lower )
				break;

			_mid = _lower + (((_upper-_lower) >> 1) & ~1);
			if ( data[p] < _puma_parser_trans_keys[_mid] )
				_upper = _mid - 2;
			else if ( data[p] > _puma_parser_trans_keys[_mid+1] )
				_lower = _mid + 2;
			else {
				_trans += ((_mid - _keys)>>1);
				break _match;
			}
		}
		_trans += _klen;
	}
	} while (false);

	_trans = _puma_parser_indicies[_trans];
	cs = _puma_parser_trans_targs[_trans];

	if ( _puma_parser_trans_actions[_trans] != 0 ) {
		_acts = _puma_parser_trans_actions[_trans];
		_nacts = (int) _puma_parser_actions[_acts++];
		while ( _nacts-- > 0 )
	{
			switch ( _puma_parser_actions[_acts++] )
			{
	case 0:
// line 15 "ext/puma_http11/http11_parser.java.rl"
	{parser.mark = p; }
	break;
	case 1:
// line 17 "ext/puma_http11/http11_parser.java.rl"
	{ parser.field_start = p; }
	break;
	case 2:
// line 18 "ext/puma_http11/http11_parser.java.rl"
	{ /* FIXME stub */ }
	break;
	case 3:
// line 19 "ext/puma_http11/http11_parser.java.rl"
	{ 
    parser.field_len = p-parser.field_start;
  }
	break;
	case 4:
// line 23 "ext/puma_http11/http11_parser.java.rl"
	{ parser.mark = p; }
	break;
	case 5:
// line 24 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.http_field(runtime, parser.data, parser.buffer, parser.field_start, parser.field_len, parser.mark, p-parser.mark);
  }
	break;
	case 6:
// line 27 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.request_method(runtime, parser.data, parser.buffer, parser.mark, p-parser.mark);
  }
	break;
	case 7:
// line 30 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.request_uri(runtime, parser.data, parser.buffer, parser.mark, p-parser.mark);
  }
	break;
	case 8:
// line 33 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.fragment(runtime, parser.data, parser.buffer, parser.mark, p-parser.mark);
  }
	break;
	case 9:
// line 37 "ext/puma_http11/http11_parser.java.rl"
	{parser.query_start = p; }
	break;
	case 10:
// line 38 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.query_string(runtime, parser.data, parser.buffer, parser.query_start, p-parser.query_start);
  }
	break;
	case 11:
// line 42 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.server_protocol(runtime, parser.data, parser.buffer, parser.mark, p-parser.mark);
  }
	break;
	case 12:
// line 46 "ext/puma_http11/http11_parser.java.rl"
	{
    Http11.request_path(runtime, parser.data, parser.buffer, parser.mark, p-parser.mark);
  }
	break;
	case 13:
// line 50 "ext/puma_http11/http11_parser.java.rl"
	{ 
    parser.body_start = p + 1;
    http.header_done(runtime, parser.data, parser.buffer, p + 1, pe - p - 1);
    { p += 1; _goto_targ = 5; if (true)  continue _goto;}
  }
	break;
// line 404 "ext/puma_http11/org/jruby/puma/Http11Parser.java"
			}
		}
	}

case 2:
	if ( cs == 0 ) {
		_goto_targ = 5;
		continue _goto;
	}
	if ( ++p != pe ) {
		_goto_targ = 1;
		continue _goto;
	}
case 4:
case 5:
	}
	break; }
	}

// line 114 "ext/puma_http11/http11_parser.java.rl"

     parser.cs = cs;
     parser.nread += (p - off);
     
     assert p <= pe                  : "buffer overflow after parsing execute";
     assert parser.nread <= len      : "nread longer than length";
     assert parser.body_start <= len : "body starts after buffer end";
     assert parser.mark < len        : "mark is after buffer end";
     assert parser.field_len <= len  : "field has length longer than whole buffer";
     assert parser.field_start < len : "field starts after buffer end";

     return parser.nread;
   }

   public int finish() {
    if(has_error()) {
      return -1;
    } else if(is_finished()) {
      return 1;
    } else {
      return 0;
    }
  }

  public boolean has_error() {
    return parser.cs == puma_parser_error;
  }

  public boolean is_finished() {
    return parser.cs == puma_parser_first_final;
  }
}
