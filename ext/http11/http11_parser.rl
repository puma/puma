#include "http11_parser.h"
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define MARK(S,F) (S)->mark = (F);

/** machine **/
%%{
	machine http_parser;

    	action mark {MARK(parser, fpc); }

	action start_field { parser->field_start = fpc; }	
	action write_field { 
	       parser->field_len = (p - parser->field_start);
	}

	action start_value { MARK(parser, fpc); }
	action write_value { 
      	       assert(p - (parser->mark - 1) >= 0 && "buffer overflow"); 
	       if(parser->http_field != NULL) {
	       	       parser->http_field(parser->data, 
		       		parser->field_start, parser->field_len, 
				parser->mark+1, p - (parser->mark +1));
		}
	}
	action request_method { 
      	       assert(p - parser->mark >= 0 && "buffer overflow"); 
	       if(parser->request_method != NULL) 
	       	       parser->request_method(parser->data, parser->mark, p - parser->mark);
	}
	action request_uri { 
       	       assert(p - parser->mark >= 0 && "buffer overflow"); 
	       if(parser->request_uri != NULL)
	       	       parser->request_uri(parser->data, parser->mark, p - parser->mark);
	}
	action query_string { 
       	       assert(p - parser->mark >= 0 && "buffer overflow"); 
	       if(parser->query_string != NULL)
	       	       parser->query_string(parser->data, parser->mark, p - parser->mark);
	}

	action http_version {	
       	       assert(p - parser->mark >= 0 && "buffer overflow"); 
	       if(parser->http_version != NULL)
	       	       parser->http_version(parser->data, parser->mark, p - parser->mark);
	}

    	action done { 
	       parser->body_start = p+1; 
	       if(parser->header_done != NULL)
	       	       parser->header_done(parser->data, p, 0);
	       fbreak;
	}


	#### HTTP PROTOCOL GRAMMAR
        # line endings
        CRLF = "\r\n";

        # character types
        CTL = (cntrl | 127);
        safe = ("$" | "-" | "_" | ".");
        extra = ("!" | "*" | "'" | "(" | ")" | ",");
        reserved = (";" | "/" | "?" | ":" | "@" | "&" | "=" | "+");
        unsafe = (CTL | " " | "\"" | "#" | "%" | "<" | ">");
        national = any -- (alpha | digit | reserved | extra | safe | unsafe);
        unreserved = (alpha | digit | safe | extra | national);
        escape = ("%" xdigit xdigit);
        uchar = (unreserved | escape);
        pchar = (uchar | ":" | "@" | "&" | "=" | "+");
        tspecials = ("(" | ")" | "<" | ">" | "@" | "," | ";" | ":" | "\\" | "\"" | "/" | "[" | "]" | "?" | "=" | "{" | "}" | " " | "\t");

        # elements
        token = (ascii -- (CTL | tspecials));

        # URI schemes and absolute paths
        scheme = ( alpha | digit | "+" | "-" | "." )* ;
        absolute_uri = (scheme ":" (uchar | reserved )*) >mark %request_uri;

        path = (pchar+ ( "/" pchar* )*) ;
        query = ( uchar | reserved )* >mark %query_string ;
        param = ( pchar | "/" )* ;
        params = (param ( ";" param )*) ;
        rel_path = (path? (";" params)?) %request_uri  ("?" query)? ;
        absolute_path = ("/" rel_path) >mark ;
        
        Request_URI = ("*" >mark %request_uri | absolute_uri | absolute_path) ;
        Method = ("OPTIONS"| "GET" | "HEAD" | "POST" | "PUT" | "DELETE" | "TRACE") >mark %request_method;
        
        http_number = (digit+ "." digit+) ;
        HTTP_Version = ("HTTP/" http_number) >mark %http_version ;
        Request_Line = (Method " " Request_URI " " HTTP_Version CRLF) ;
	
	field_name = (token -- ":")+ >start_field %write_field;

        field_value = any* >start_value %write_value;

        message_header = field_name ":" field_value :> CRLF;
	
        Request = Request_Line (message_header)* ( CRLF @done);

	main := Request;
}%%

/** Data **/
%% write data;

int http_parser_init(http_parser *parser)  {
    int cs = 0;
    %% write init;
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

    %% write exec;

    parser->cs = cs;
    parser->nread = p - buffer;
    if(parser->body_start) {
        /* final \r\n combo encountered so stop right here */
	%%write eof;
	parser->nread++;
    }

    return(parser->nread);
}

int http_parser_finish(http_parser *parser)
{
	int cs = parser->cs;

	%%write eof;

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
