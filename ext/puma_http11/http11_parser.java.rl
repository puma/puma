package org.jruby.puma;

import org.jruby.Ruby;
import org.jruby.RubyHash;
import org.jruby.RubyString;
import org.jruby.util.ByteList;

public class Http11Parser {

    private final RubyString[] envStrings;

    public Http11Parser(RubyString[] envStrings) {
        this.envStrings = envStrings;
    }

    /*
     * capitalizes all lower-case ASCII characters,
     * converts dashes to underscores, and underscores to commas.
     */
    static void snake_upcase_char(byte[] c, int off) {
        byte ch = c[off];
        if (ch >= 'a' && ch <= 'z')
          c[off] = (byte) (ch & ~0x20);
        else if (ch == '_')
          c[off] = ',';
        else if (ch == '-')
          c[off] = '_';
    }

/** Machine **/

%%{

  machine puma_parser;

  action mark {this.mark = fpc; }

  action start_field { this.field_start = fpc; }
  action snake_upcase_field { snake_upcase_char(this.buffer, fpc); }
  action write_field { 
    this.field_len = fpc-this.field_start;
  }

  action start_value { this.mark = fpc; }
  action write_value {
    Http11.http_field(runtime, this.data, envStrings, this.buffer, this.field_start, this.field_len, this.mark, fpc-this.mark);
  }
  action request_method {
    Http11.request_method(runtime, this.data, this.buffer, this.mark, fpc-this.mark);
  }
  action request_uri {
    Http11.request_uri(runtime, this.data, this.buffer, this.mark, fpc-this.mark);
  }
  action fragment {
    Http11.fragment(runtime, this.data, this.buffer, this.mark, fpc-this.mark);
  }
  
  action start_query {this.query_start = fpc; }
  action query_string {
    Http11.query_string(runtime, this.data, this.buffer, this.query_start, fpc-this.query_start);
  }

  action server_protocol {
    Http11.server_protocol(runtime, this.data, this.buffer, this.mark, fpc-this.mark);
  }

  action request_path {
    Http11.request_path(runtime, this.data, this.buffer, this.mark, fpc-this.mark);
  }

  action done { 
    this.body_start = fpc + 1;
    http.header_done(runtime, this.data, this.buffer, fpc + 1, pe - fpc - 1);
    fbreak;
  }

  include puma_parser_common "http11_parser_common.rl";

}%%

/** Data **/
%% write data noentry;

   public static interface ElementCB {
     public void call(Ruby runtime, RubyHash data, ByteList buffer, int at, int length);
   }

   public static interface FieldCB {
     public void call(Ruby runtime, RubyHash data, ByteList buffer, int field, int flen, int value, int vlen);
   }

   int cs;
   int body_start;
   int content_len;
   int nread;
   int mark;
   int field_start;
   int field_len;
   int query_start;

   RubyHash data;
   byte[] buffer;

   public void init() {
       cs = 0;

       %% write init;

       body_start = 0;
       content_len = 0;
       mark = 0;
       nread = 0;
       field_len = 0;
       field_start = 0;
   }

   public int execute(Ruby runtime, Http11 http, ByteList buffer, int off) {
     int p, pe;
     int cs = this.cs;
     int len = buffer.length();
     int beg = buffer.begin();
     assert off<=len : "offset past end of buffer";

     p = beg + off;
     pe = beg + len;
     byte[] data = buffer.unsafeBytes();
     this.buffer = data;

     %% write exec;

     this.cs = cs;
     this.nread += (p - off);
     
     assert p <= pe                  : "buffer overflow after parsing execute";
     assert this.nread <= len      : "nread longer than length";
     assert this.body_start <= len : "body starts after buffer end";
     assert this.mark < len        : "mark is after buffer end";
     assert this.field_len <= len  : "field has length longer than whole buffer";
     assert this.field_start < len : "field starts after buffer end";

     return this.nread;
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
    return this.cs == puma_parser_error;
  }

  public boolean is_finished() {
    return this.cs == puma_parser_first_final;
  }
}
