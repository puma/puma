# frozen_string_literal: true

require 'strscan'

module Puma
  # Also defined by the puma_http11 extension. Reopening it here is harmless and
  # keeps the error class available when the extension is not loaded.
  class HttpParserError < StandardError; end

  # A pure Ruby HTTP/1.x request parser, written as a drop-in replacement for
  # the C extension's Puma::HttpParser. It transcribes the Ragel grammar in
  # ext/puma_http11/http11_parser_common.rl and aims to behave identically:
  # the same env keys and values, the same errors and messages, the same
  # +nread+, and the same in-place upcasing of header names in the buffer,
  # which Puma::Client relies on when it reports bad headers.
  #
  # Like the C parser it is a resumable state machine. Each call to #execute
  # consumes the bytes from +start+ to the end of the buffer and leaves the
  # parser in whichever element it stopped in: method, URI, fragment, protocol,
  # field name or field value. Element start offsets are absolute, so the
  # caller must pass the whole buffer each time and append new data to it.
  #
  # Each element's bytes are consumed with one anchored, binary regex of a
  # single character class, so matching is linear and a bad byte is rejected
  # as soon as it arrives, even in the middle of a line.
  #
  # Puma uses this class in place of the C parser when the extension cannot be
  # loaded or when the PUMA_PURE_RUBY_PARSER environment variable is set.
  class RubyHttpParser
    # Reads a length limit from the environment the same way the JRuby
    # extension does (ext/puma_http11/org/jruby/puma/Http11.java). Returns the
    # limit and the text the error message uses for it.
    def self.length_limit(env_name, default, default_text)
      value = ENV[env_name]
      return [default, default_text] if value.nil? || value.empty?

      if value.match?(/\A\+?[0-9]+\z/) && (n = value.to_i) > 0 && n <= 0x7fff_ffff
        [n, n.to_s]
      else
        $stderr.puts "The value #{value} for #{env_name} is invalid. Using default value #{default} instead."
        [default, default_text]
      end
    end
    private_class_method :length_limit

    # Limits and messages match ext/puma_http11/puma_http11.c, including its
    # unevaluated arithmetic, e.g. "(1024 * 12)".
    MAX_FIELD_NAME_LENGTH = 256
    MAX_FIELD_NAME_LENGTH_ERR = "HTTP element FIELD_NAME is longer than the 256 allowed length (was %d)"
    MAX_FIELD_VALUE_LENGTH = 80 * 1024
    MAX_FIELD_VALUE_LENGTH_ERR = "HTTP element FIELD_VALUE is longer than the 80 * 1024 allowed length (was %d)"
    MAX_FRAGMENT_LENGTH = 1024
    MAX_FRAGMENT_LENGTH_ERR = "HTTP element FRAGMENT is longer than the 1024 allowed length (was %d)"
    MAX_HEADER_LENGTH = 1024 * (80 + 32)
    MAX_HEADER_LENGTH_ERR = "HTTP element HEADER is longer than the (1024 * (80 + 32)) allowed length (was %d)"

    limit, text = length_limit("PUMA_REQUEST_URI_MAX_LENGTH", 1024 * 12, "(1024 * 12)")
    MAX_REQUEST_URI_LENGTH = limit
    MAX_REQUEST_URI_LENGTH_ERR = "HTTP element REQUEST_URI is longer than the #{text} allowed length (was %d)".freeze

    limit, text = length_limit("PUMA_REQUEST_PATH_MAX_LENGTH", 8192, "(8192)")
    MAX_REQUEST_PATH_LENGTH = limit
    MAX_REQUEST_PATH_LENGTH_ERR = "HTTP element REQUEST_PATH is longer than the #{text} allowed length (was %d)".freeze

    limit, text = length_limit("PUMA_QUERY_STRING_MAX_LENGTH", 1024 * 10, "(1024 * 10)")
    MAX_QUERY_STRING_LENGTH = limit
    MAX_QUERY_STRING_LENGTH_ERR = "HTTP element QUERY_STRING is longer than the #{text} allowed length (was %d)".freeze

    PARSE_ERR = "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?"
    START_ERR = "Requested start is after data buffer end."

    REQUEST_METHOD = "REQUEST_METHOD"
    REQUEST_URI = "REQUEST_URI"
    FRAGMENT = "FRAGMENT"
    QUERY_STRING = "QUERY_STRING"
    SERVER_PROTOCOL = "SERVER_PROTOCOL"
    REQUEST_PATH = "REQUEST_PATH"

    # Runs of bytes allowed in each element, transcribed from the grammar.
    # Bytes above 127 are allowed wherever the grammar's +national+ class or
    # its "any -- CTL" field value allows them.
    METHOD_RUN = /[A-Z0-9$\-_.]*/n                   # upper | digit | safe
    SCHEME_RUN = /[A-Za-z0-9+\-.]*/n                 # absolute_uri scheme
    URI_RUN    = /[^\x00-\x20"#<>\x7f]*/n            # uchar | reserved
    PATH_RUN   = /[^\x00-\x20"#<>?{}`\\\x7f]*/n      # path_char | "/"
    DIGIT_RUN  = /[0-9]*/n
    TOKEN_RUN  = /[!\#$%&'*+\-.^_`|~0-9A-Za-z]*/n    # token -- ":"
    SPACE_RUN  = / */n
    VALUE_RUN  = /[^\x00-\x08\x0a-\x1f\x7f]*/n       # (any -- CTL) | "\t"

    def self.byte_table(run)
      Array.new(256) { |b| run.match(b.chr)[0].bytesize == 1 }.freeze
    end
    private_class_method :byte_table

    METHOD_BYTE = byte_table(METHOD_RUN)
    SCHEME_BYTE = byte_table(SCHEME_RUN)
    TOKEN_BYTE  = byte_table(TOKEN_RUN)
    VALUE_BYTE  = byte_table(VALUE_RUN)

    MAX_METHOD_LENGTH = 20
    PROTOCOL_PREFIX = "HTTP/".bytes.freeze

    CR = 13
    LF = 10
    SPACE = 32
    HASH = 35
    STAR = 42
    DOT = 46
    SLASH = 47
    COLON = 58
    QUESTION = 63

    # Parser states. ERROR and START share the C parser's numbering.
    ERROR = 0
    START = 1
    METHOD = 2
    URI_START = 3
    URI_STAR = 4
    URI_SCHEME = 5
    URI_ABSOLUTE = 6
    URI_PATH = 7
    URI_QUERY = 8
    URI_FRAGMENT = 9
    PROTOCOL_PREFIX_START = 10 # 10..14 match the bytes of "HTTP/"
    PROTOCOL_MAJOR_START = 15
    PROTOCOL_MAJOR = 16
    PROTOCOL_MINOR_START = 17
    PROTOCOL_MINOR = 18
    REQUEST_LINE_LF = 19
    FIELD_START = 20
    FIELD_NAME = 21
    VALUE_SPACES = 22
    FIELD_VALUE = 23
    FIELD_LF = 24
    HEADERS_END_LF = 25
    DONE = 26
    PROTOCOL_PREFIX_STATES = (PROTOCOL_PREFIX_START...PROTOCOL_MAJOR_START).freeze

    # Interned env keys for common headers, keyed by the snake-upcased field
    # name. The C parser stores CONTENT_LENGTH and CONTENT_TYPE without the
    # HTTP_ prefix; every other header gets it.
    FIELD_KEYS = %w[
      ACCEPT ACCEPT_CHARSET ACCEPT_ENCODING ACCEPT_LANGUAGE ALLOW AUTHORIZATION
      CACHE_CONTROL CONNECTION CONTENT_ENCODING COOKIE DATE DNT EXPECT FORWARDED
      FROM HOST IF_MATCH IF_MODIFIED_SINCE IF_NONE_MATCH IF_RANGE
      IF_UNMODIFIED_SINCE KEEP_ALIVE MAX_FORWARDS ORIGIN PRAGMA PRIORITY
      PROXY_AUTHORIZATION RANGE REFERER SEC_CH_UA SEC_CH_UA_MOBILE
      SEC_CH_UA_PLATFORM SEC_FETCH_DEST SEC_FETCH_MODE SEC_FETCH_SITE
      SEC_FETCH_USER TE TRAILER TRANSFER_ENCODING UPGRADE
      UPGRADE_INSECURE_REQUESTS USER_AGENT VIA WARNING X_FORWARDED_FOR
      X_FORWARDED_HOST X_FORWARDED_PROTO X_REAL_IP X_REQUEST_ID
    ].to_h { |name| [name, -"HTTP_#{name}"] }
      .merge("CONTENT_LENGTH" => "CONTENT_LENGTH", "CONTENT_TYPE" => "CONTENT_TYPE")
      .freeze

    def initialize
      reset
    end

    # Resets the parser to its initial state so it can be reused.
    def reset
      @cs = START
      @nread = 0
      @mark = 0
      @query_start = 0
      @field_start = 0
      @field_len = 0
      @field_name = nil
      @body = nil
      @scanner&.string = "" # release the caller's buffer
      nil
    end

    # Parses +buffer+ from byte offset +start+, filling +env+ as each element
    # completes. Returns the total number of bytes parsed so far. Raises
    # Puma::HttpParserError on malformed input or when a length limit is
    # exceeded; check #finished? to see whether the header block is complete.
    def execute(env, buffer, start)
      len = buffer.bytesize
      raise HttpParserError, START_ERR if start >= len

      # Matching uses a binary view so any buffer encoding behaves like the
      # binary socket data Puma reads. Header names are upcased in place in
      # +buffer+, as the C parser does, unless it is frozen.
      buf = buffer.encoding == Encoding::BINARY ? buffer : buffer.b
      mutate = !buffer.frozen?
      ss = @scanner
      if ss.nil?
        ss = @scanner = StringScanner.new(buf)
      elsif !ss.string.equal?(buf)
        ss.string = buf
      end

      cs = @cs
      p = start
      mark = @mark
      query_start = @query_start
      field_start = @field_start
      field_len = @field_len
      name = @field_name

      while p < len
        case cs
        when FIELD_VALUE
          ss.pos = p
          p += ss.skip(VALUE_RUN)
          break if p == len
          if buf.getbyte(p) == CR
            store_field env, buf, name, field_len, mark, p - mark
            cs = FIELD_LF
            p += 1
          else
            cs = ERROR
            break
          end

        when FIELD_LF
          if buf.getbyte(p) == LF
            cs = FIELD_START
            p += 1
          else
            cs = ERROR
            break
          end

        when FIELD_START
          b = buf.getbyte(p)
          if b == CR
            cs = HEADERS_END_LF
            p += 1
          elsif TOKEN_BYTE[b]
            field_start = p
            name = nil
            cs = FIELD_NAME
          else
            cs = ERROR
            break
          end

        when FIELD_NAME
          segment_start = p
          ss.pos = p
          n = ss.skip(TOKEN_RUN)
          if n > 0
            # The C parser snake-upcases each name byte in the buffer as it
            # consumes it, including in a name that then turns out invalid.
            up = buf.byteslice(p, n)
            changed = up.upcase!
            changed = up.tr!("_-", ",_") || changed
            if changed && mutate
              write_bytes buffer, p, up
              write_bytes buf, p, up unless buf.equal?(buffer)
            end
            p += n
          end
          break if p == len
          if buf.getbyte(p) == COLON
            field_len = p - field_start
            # When the whole name was consumed in this call it is already in
            # hand; otherwise read it back from the buffer.
            name = segment_start == field_start ? up : read_field_name(buf, field_start, field_len, mutate)
            mark = p + 1
            cs = VALUE_SPACES
            p += 1
          else
            cs = ERROR
            break
          end

        when VALUE_SPACES
          # Mirrors where the C parser's start_value action leaves its mark:
          # on the first byte after the spaces, or on the last space when the
          # value is all spaces. Leading tabs are part of the value.
          ss.pos = p
          n = ss.skip(SPACE_RUN)
          if n > 0
            p += n
            mark = p - 1
          end
          break if p == len
          b = buf.getbyte(p)
          if b == CR
            store_field env, buf, name, field_len, mark, p - mark
            cs = FIELD_LF
            p += 1
          elsif VALUE_BYTE[b]
            mark = p
            cs = FIELD_VALUE
          else
            cs = ERROR
            break
          end

        when HEADERS_END_LF
          if buf.getbyte(p) == LF
            p += 1
            @body = buf.byteslice(p, len - p)
            cs = DONE
            break
          else
            cs = ERROR
            break
          end

        when START
          if METHOD_BYTE[buf.getbyte(p)]
            mark = p
            cs = METHOD
          else
            cs = ERROR
            break
          end

        when METHOD
          ss.pos = p
          p += ss.skip(METHOD_RUN)
          if p - mark > MAX_METHOD_LENGTH
            p = mark + MAX_METHOD_LENGTH
            cs = ERROR
            break
          end
          break if p == len
          if buf.getbyte(p) == SPACE
            env[REQUEST_METHOD] = buf.byteslice(mark, p - mark)
            cs = URI_START
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_START
          b = buf.getbyte(p)
          mark = p
          if b == SLASH
            cs = URI_PATH
          elsif b == STAR
            cs = URI_STAR
          elsif b == COLON
            cs = URI_ABSOLUTE
          elsif SCHEME_BYTE[b]
            cs = URI_SCHEME
          else
            cs = ERROR
            break
          end
          p += 1

        when URI_PATH
          ss.pos = p
          p += ss.skip(PATH_RUN)
          break if p == len
          b = buf.getbyte(p)
          if b == QUESTION
            request_path env, buf, mark, p
            query_start = p + 1
            cs = URI_QUERY
            p += 1
          elsif b == SPACE || b == HASH
            request_path env, buf, mark, p
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == SPACE ? PROTOCOL_PREFIX_START : URI_FRAGMENT
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_QUERY
          ss.pos = p
          p += ss.skip(URI_RUN)
          break if p == len
          b = buf.getbyte(p)
          if b == SPACE || b == HASH
            query_string env, buf, query_start, p
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == SPACE ? PROTOCOL_PREFIX_START : URI_FRAGMENT
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_SCHEME
          ss.pos = p
          p += ss.skip(SCHEME_RUN)
          break if p == len
          if buf.getbyte(p) == COLON
            cs = URI_ABSOLUTE
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_ABSOLUTE
          ss.pos = p
          p += ss.skip(URI_RUN)
          break if p == len
          b = buf.getbyte(p)
          if b == SPACE || b == HASH
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == SPACE ? PROTOCOL_PREFIX_START : URI_FRAGMENT
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_STAR
          b = buf.getbyte(p)
          if b == SPACE || b == HASH
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == SPACE ? PROTOCOL_PREFIX_START : URI_FRAGMENT
            p += 1
          else
            cs = ERROR
            break
          end

        when URI_FRAGMENT
          ss.pos = p
          p += ss.skip(URI_RUN)
          break if p == len
          if buf.getbyte(p) == SPACE
            n = p - mark
            raise HttpParserError, format(MAX_FRAGMENT_LENGTH_ERR, n) if n > MAX_FRAGMENT_LENGTH
            env[FRAGMENT] = buf.byteslice(mark, n)
            mark = p + 1
            cs = PROTOCOL_PREFIX_START
            p += 1
          else
            cs = ERROR
            break
          end

        when PROTOCOL_PREFIX_STATES
          index = cs - PROTOCOL_PREFIX_START
          if buf.getbyte(p) == PROTOCOL_PREFIX[index]
            mark = p if index == 0
            cs += 1
            p += 1
          else
            cs = ERROR
            break
          end

        when PROTOCOL_MAJOR_START, PROTOCOL_MINOR_START
          b = buf.getbyte(p)
          if b >= 48 && b <= 57
            cs += 1
            p += 1
          else
            cs = ERROR
            break
          end

        when PROTOCOL_MAJOR
          ss.pos = p
          p += ss.skip(DIGIT_RUN)
          break if p == len
          if buf.getbyte(p) == DOT
            cs = PROTOCOL_MINOR_START
            p += 1
          else
            cs = ERROR
            break
          end

        when PROTOCOL_MINOR
          ss.pos = p
          p += ss.skip(DIGIT_RUN)
          break if p == len
          if buf.getbyte(p) == CR
            env[SERVER_PROTOCOL] = buf.byteslice(mark, p - mark)
            cs = REQUEST_LINE_LF
            p += 1
          else
            cs = ERROR
            break
          end

        when REQUEST_LINE_LF
          if buf.getbyte(p) == LF
            cs = FIELD_START
            p += 1
          else
            cs = ERROR
            break
          end

        else # DONE accepts no more input, and ERROR stays put
          cs = ERROR
          break
        end
      end

      # A length-limit error raised above skips these updates, leaving
      # #error? false and #nread unchanged, as in the C parser.
      @cs = cs
      @nread += p - start
      @mark = mark
      @query_start = query_start
      @field_start = field_start
      @field_len = field_len
      @field_name = name

      if @nread > MAX_HEADER_LENGTH
        raise HttpParserError, format(MAX_HEADER_LENGTH_ERR, @nread)
      end
      raise HttpParserError, PARSE_ERR if cs == ERROR

      @nread
    end

    # Returns true if the header block has been parsed.
    def finish
      finished?
    end

    def error?
      @cs == ERROR
    end

    def finished?
      @cs == DONE
    end

    # Returns the number of bytes parsed since the last reset.
    def nread
      @nread
    end

    # Returns the bytes that followed the header block in the buffer, or nil
    # until the header block is complete.
    def body
      @body
    end

    private

    def request_path(env, buf, from, to)
      n = to - from
      raise HttpParserError, format(MAX_REQUEST_PATH_LENGTH_ERR, n) if n > MAX_REQUEST_PATH_LENGTH
      env[REQUEST_PATH] = buf.byteslice(from, n)
    end

    def query_string(env, buf, from, to)
      n = to - from
      raise HttpParserError, format(MAX_QUERY_STRING_LENGTH_ERR, n) if n > MAX_QUERY_STRING_LENGTH
      env[QUERY_STRING] = buf.byteslice(from, n)
    end

    def request_uri(env, buf, from, to)
      n = to - from
      raise HttpParserError, format(MAX_REQUEST_URI_LENGTH_ERR, n) if n > MAX_REQUEST_URI_LENGTH
      env[REQUEST_URI] = buf.byteslice(from, n)
    end

    # Stores one header, as http_field in puma_http11.c does: lengths are
    # checked before the value is trimmed, the key is interned UTF-8, and a
    # repeated header is appended to the existing value after ", ".
    def store_field(env, buf, name, field_len, mark, value_len)
      if field_len > MAX_FIELD_NAME_LENGTH
        raise HttpParserError, format(MAX_FIELD_NAME_LENGTH_ERR, field_len)
      end
      if value_len > MAX_FIELD_VALUE_LENGTH
        raise HttpParserError, format(MAX_FIELD_VALUE_LENGTH_ERR, value_len)
      end

      key = FIELD_KEYS[name] || -"HTTP_#{name}"

      value = buf.byteslice(mark, value_len)
      # The grammar admits no whitespace in a value other than spaces and
      # tabs, so strip! trims exactly what the C parser trims.
      value.strip!

      existing = env[key]
      if existing.nil?
        env[key] = value
      else
        existing << ", " << value
      end
    end

    # Reads back a field name that spanned more than one #execute call. Its
    # bytes are already snake-upcased in +buf+ unless the buffer is frozen.
    def read_field_name(buf, field_start, field_len, mutated)
      name = buf.byteslice(field_start, field_len)
      unless mutated
        name.upcase!
        name.tr!("_-", ",_")
      end
      name
    end

    if "".respond_to?(:bytesplice)
      def write_bytes(str, pos, bytes)
        if str.encoding == Encoding::BINARY
          str.bytesplice(pos, bytes.bytesize, bytes)
        else
          bytes.bytesize.times { |i| str.setbyte(pos + i, bytes.getbyte(i)) }
        end
      end
    else
      def write_bytes(str, pos, bytes)
        bytes.bytesize.times { |i| str.setbyte(pos + i, bytes.getbyte(i)) }
      end
    end
  end
end
