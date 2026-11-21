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

    MAX_METHOD_LENGTH = 20

    PARSE_ERR = "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?"
    START_ERR = "Requested start is after data buffer end."

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

    # The FIELD_KEYS names as clients spell them: capitalized words, all
    # lowercase (as HTTP/2 proxies and Chrome's sec-ch-* headers send them),
    # and some irregular capitals. Each maps to its env key, its snake-upcased
    # form and whether snake-upcasing changes it. Built once and frozen;
    # nothing is ever added for names seen in requests. Built in a method,
    # like the byte tables, so YJIT doesn't compile a block that reads a
    # constant.
    def self.header_table(field_keys, irregular)
      spellings = field_keys.keys.flat_map do |up|
        [up.split("_").map(&:capitalize).join("-"), up.downcase.tr("_", "-")]
      end
      (spellings + irregular).uniq.to_h { |raw|
        up = raw.upcase.tr("_-", ",_")
        [raw.b.freeze, [field_keys.fetch(up), up.b.freeze, raw != up].freeze]
      }.freeze
    end
    private_class_method :header_table

    HEADER_TABLE = header_table(FIELD_KEYS, %w[DNT TE Sec-CH-UA Sec-CH-UA-Mobile Sec-CH-UA-Platform X-Real-IP X-Request-ID])
    HEADER_NAME_MAX = HEADER_TABLE.each_key.map(&:bytesize).max

    # Bytes VALUE_RUN does not allow.
    VALUE_CTL = /[\x00-\x08\x0a-\x1f\x7f]/n

    # The parsing methods below refer to no constants except to raise errors.
    # States are symbols, bytes are integer literals, and everything else is
    # copied here into instance variables. Under YJIT, filling or clearing a
    # constant cache invalidates the compiled code that reads it, and on Ruby
    # 4.0 and 4.1-dev that code can be left exiting to the interpreter on every
    # call, for the life of the process, so the parser ran about twice as
    # slow. Both happen in ordinary use: the first query string after a run of
    # requests without one fills caches, and code anywhere defining a constant
    # with the same name, such as SPACE, clears them. Reported as
    # https://bugs.ruby-lang.org/issues/22617. See test/test_http_parser_yjit.rb.
    def initialize
      @method_run = METHOD_RUN
      @scheme_run = SCHEME_RUN
      @uri_run = URI_RUN
      @path_run = PATH_RUN
      @digit_run = DIGIT_RUN
      @token_run = TOKEN_RUN
      @space_run = SPACE_RUN
      @value_run = VALUE_RUN
      @method_byte = METHOD_BYTE
      @scheme_byte = SCHEME_BYTE
      @token_byte = TOKEN_BYTE
      @value_byte = VALUE_BYTE
      @max_method_length = MAX_METHOD_LENGTH
      @max_request_uri_length = MAX_REQUEST_URI_LENGTH
      @max_request_path_length = MAX_REQUEST_PATH_LENGTH
      @max_query_string_length = MAX_QUERY_STRING_LENGTH
      @max_fragment_length = MAX_FRAGMENT_LENGTH
      @max_field_name_length = MAX_FIELD_NAME_LENGTH
      @max_field_value_length = MAX_FIELD_VALUE_LENGTH
      @max_header_length = MAX_HEADER_LENGTH
      @field_keys = FIELD_KEYS
      @header_table = HEADER_TABLE
      @header_name_max = HEADER_NAME_MAX
      @value_ctl = VALUE_CTL
      @binary = Encoding::BINARY
      @scanner = StringScanner.new("")
      reset
    end

    # Resets the parser to its initial state so it can be reused.
    def reset
      @cs = :start
      @nread = 0
      @mark = 0
      @query_start = 0
      @field_start = 0
      @field_len = 0
      @field_name = nil
      @body = nil
      @scanner.string = "" # release the caller's buffer
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
      buf = buffer.encoding == @binary ? buffer : buffer.b
      mutate = !buffer.frozen?
      ss = @scanner
      ss.string = buf unless ss.string.equal?(buf)

      cs = @cs
      p = start
      mark = @mark
      query_start = @query_start
      field_start = @field_start
      field_len = @field_len
      name = @field_name
      key = nil # the env key, when the name shortcut found it

      while p < len
        case cs
        when :field_value
          ss.pos = p
          p += ss.skip(@value_run)
          break if p == len
          if buf.getbyte(p) == 13 # "\r"
            store_field env, buf, key, name, field_len, mark, p - mark
            cs = :field_lf
            p += 1
          else
            cs = :error
            break
          end

        when :field_lf
          if buf.getbyte(p) == 10 # "\n"
            cs = :field_start
            p += 1
          else
            cs = :error
            break
          end

        when :field_start
          b = buf.getbyte(p)
          if b == 13 # "\r"
            cs = :headers_end_lf
            p += 1
          elsif @token_byte[b]
            field_start = p
            name = nil
            key = nil
            cs = :field_name
            # Name shortcut: one lookup of a common name, as clients spell it,
            # stands in for :field_name's scan and snake-upcasing and for the
            # env key lookup. A hit is a valid name. When the colon is too far
            # away to end a name in the table, there is no lookup, so a line
            # without one isn't sliced. On a miss, :field_name runs as usual.
            c = buf.index(":", p)
            if c && c - p <= @header_name_max && (entry = @header_table[buf.byteslice(p, c - p)])
              if entry[2] && mutate
                write_bytes buffer, p, entry[1]
                write_bytes buf, p, entry[1] unless buf.equal?(buffer)
              end
              key = entry[0]
              name = entry[1]
              field_len = c - p
              mark = c + 1
              cs = :value_spaces
              p = c + 1
            end
          else
            cs = :error
            break
          end

        when :field_name
          segment_start = p
          ss.pos = p
          n = ss.skip(@token_run)
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
          if buf.getbyte(p) == 58 # ":"
            field_len = p - field_start
            # When the whole name was consumed in this call it is already in
            # hand; otherwise read it back from the buffer.
            name = segment_start == field_start ? up : read_field_name(buf, field_start, field_len, mutate)
            mark = p + 1
            cs = :value_spaces
            p += 1
          else
            cs = :error
            break
          end

        when :value_spaces
          # Value shortcut: a value whose line is complete, with no bytes the
          # grammar rejects, is stored in one step. Otherwise, or when a length
          # limit would be exceeded, the code below handles it, so errors are
          # raised in only one place. The value starts after the spaces. For
          # an all-space value the code below marks the last space instead,
          # but a length of 1 rather than 0 can't reach the limit, and both
          # strip to "".
          v = p
          v += 1 while buf.getbyte(v) == 32 # " "
          r = buf.index("\r", v)
          if r && buf.getbyte(r + 1) == 10 # "\n"
            if field_len <= @max_field_name_length && r - v <= @max_field_value_length
              value = buf.byteslice(v, r - v)
              unless value.match?(@value_ctl)
                value.strip!
                key ||= @field_keys[name] || -"HTTP_#{name}"
                existing = env[key]
                if existing.nil?
                  env[key] = value
                else
                  existing << ", " << value
                end
                mark = v
                cs = :field_start
                p = r + 2
                next
              end
            end
          end

          # Mirrors where the C parser's start_value action leaves its mark:
          # on the first byte after the spaces, or on the last space when the
          # value is all spaces. Leading tabs are part of the value.
          ss.pos = p
          n = ss.skip(@space_run)
          if n > 0
            p += n
            mark = p - 1
          end
          break if p == len
          b = buf.getbyte(p)
          if b == 13 # "\r"
            store_field env, buf, key, name, field_len, mark, p - mark
            cs = :field_lf
            p += 1
          elsif @value_byte[b]
            mark = p
            cs = :field_value
          else
            cs = :error
            break
          end

        when :headers_end_lf
          if buf.getbyte(p) == 10 # "\n"
            p += 1
            @body = buf.byteslice(p, len - p)
            cs = :done
            break
          else
            cs = :error
            break
          end

        when :start
          if @method_byte[buf.getbyte(p)]
            mark = p
            cs = :method
          else
            cs = :error
            break
          end

        when :method
          ss.pos = p
          p += ss.skip(@method_run)
          if p - mark > @max_method_length
            p = mark + @max_method_length
            cs = :error
            break
          end
          break if p == len
          if buf.getbyte(p) == 32 # " "
            env["REQUEST_METHOD"] = buf.byteslice(mark, p - mark)
            cs = :uri_start
            p += 1
          else
            cs = :error
            break
          end

        when :uri_start
          b = buf.getbyte(p)
          mark = p
          if b == 47 # "/"
            cs = :uri_path
          elsif b == 42 # "*"
            cs = :uri_star
          elsif b == 58 # ":"
            cs = :uri_absolute
          elsif @scheme_byte[b]
            cs = :uri_scheme
          else
            cs = :error
            break
          end
          p += 1

        when :uri_path
          ss.pos = p
          p += ss.skip(@path_run)
          break if p == len
          b = buf.getbyte(p)
          if b == 63 # "?"
            request_path env, buf, mark, p
            query_start = p + 1
            cs = :uri_query
            p += 1
          elsif b == 32 || b == 35 # " " or "#"
            request_path env, buf, mark, p
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == 32 ? :protocol_prefix : :uri_fragment # " "
            p += 1
          else
            cs = :error
            break
          end

        when :uri_query
          ss.pos = p
          p += ss.skip(@uri_run)
          break if p == len
          b = buf.getbyte(p)
          if b == 32 || b == 35 # " " or "#"
            query_string env, buf, query_start, p
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == 32 ? :protocol_prefix : :uri_fragment # " "
            p += 1
          else
            cs = :error
            break
          end

        when :uri_scheme
          ss.pos = p
          p += ss.skip(@scheme_run)
          break if p == len
          if buf.getbyte(p) == 58 # ":"
            cs = :uri_absolute
            p += 1
          else
            cs = :error
            break
          end

        when :uri_absolute
          ss.pos = p
          p += ss.skip(@uri_run)
          break if p == len
          b = buf.getbyte(p)
          if b == 32 || b == 35 # " " or "#"
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == 32 ? :protocol_prefix : :uri_fragment # " "
            p += 1
          else
            cs = :error
            break
          end

        when :uri_star
          b = buf.getbyte(p)
          if b == 32 || b == 35 # " " or "#"
            request_uri env, buf, mark, p
            mark = p + 1
            cs = b == 32 ? :protocol_prefix : :uri_fragment # " "
            p += 1
          else
            cs = :error
            break
          end

        when :uri_fragment
          ss.pos = p
          p += ss.skip(@uri_run)
          break if p == len
          if buf.getbyte(p) == 32 # " "
            n = p - mark
            raise HttpParserError, format(MAX_FRAGMENT_LENGTH_ERR, n) if n > @max_fragment_length
            env["FRAGMENT"] = buf.byteslice(mark, n)
            mark = p + 1
            cs = :protocol_prefix
            p += 1
          else
            cs = :error
            break
          end

        when :protocol_prefix
          # Matches the bytes of "HTTP/". Every way into this state leaves
          # +mark+ on the "H", so p - mark is the index of the next byte.
          if buf.getbyte(p) == "HTTP/".getbyte(p - mark)
            p += 1
            cs = :protocol_major_start if p - mark == 5
          else
            cs = :error
            break
          end

        when :protocol_major_start, :protocol_minor_start
          b = buf.getbyte(p)
          if b >= 48 && b <= 57 # "0".."9"
            cs = cs == :protocol_major_start ? :protocol_major : :protocol_minor
            p += 1
          else
            cs = :error
            break
          end

        when :protocol_major
          ss.pos = p
          p += ss.skip(@digit_run)
          break if p == len
          if buf.getbyte(p) == 46 # "."
            cs = :protocol_minor_start
            p += 1
          else
            cs = :error
            break
          end

        when :protocol_minor
          ss.pos = p
          p += ss.skip(@digit_run)
          break if p == len
          if buf.getbyte(p) == 13 # "\r"
            env["SERVER_PROTOCOL"] = buf.byteslice(mark, p - mark)
            cs = :request_line_lf
            p += 1
          else
            cs = :error
            break
          end

        when :request_line_lf
          if buf.getbyte(p) == 10 # "\n"
            cs = :field_start
            p += 1
          else
            cs = :error
            break
          end

        else # :done accepts no more input, and :error stays put
          cs = :error
          break
        end
      end

      # A length-limit error raised above skips these updates, leaving
      # #error? false and #nread unchanged, as in the C parser. The element
      # offsets keep their old values too, whereas the C parser has already
      # moved some of them on, so the two differ if a parser is used again
      # after such an error without #reset. Puma closes the connection instead.
      @cs = cs
      @nread += p - start
      @mark = mark
      @query_start = query_start
      @field_start = field_start
      @field_len = field_len
      @field_name = name

      if @nread > @max_header_length
        raise HttpParserError, format(MAX_HEADER_LENGTH_ERR, @nread)
      end
      raise HttpParserError, PARSE_ERR if cs == :error

      @nread
    end

    # Returns true if the header block has been parsed.
    def finish
      finished?
    end

    def error?
      @cs == :error
    end

    def finished?
      @cs == :done
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
      raise HttpParserError, format(MAX_REQUEST_PATH_LENGTH_ERR, n) if n > @max_request_path_length
      env["REQUEST_PATH"] = buf.byteslice(from, n)
    end

    def query_string(env, buf, from, to)
      n = to - from
      raise HttpParserError, format(MAX_QUERY_STRING_LENGTH_ERR, n) if n > @max_query_string_length
      env["QUERY_STRING"] = buf.byteslice(from, n)
    end

    def request_uri(env, buf, from, to)
      n = to - from
      raise HttpParserError, format(MAX_REQUEST_URI_LENGTH_ERR, n) if n > @max_request_uri_length
      env["REQUEST_URI"] = buf.byteslice(from, n)
    end

    # Stores one header, as http_field in puma_http11.c does: lengths are
    # checked before the value is trimmed, the key is interned UTF-8, and a
    # repeated header is appended to the existing value after ", ".
    def store_field(env, buf, key, name, field_len, mark, value_len)
      if field_len > @max_field_name_length
        raise HttpParserError, format(MAX_FIELD_NAME_LENGTH_ERR, field_len)
      end
      if value_len > @max_field_value_length
        raise HttpParserError, format(MAX_FIELD_VALUE_LENGTH_ERR, value_len)
      end

      key ||= @field_keys[name] || -"HTTP_#{name}"

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
        if str.encoding == @binary
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
