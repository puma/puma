#!/usr/bin/env ruby

require 'test/unit'
require 'cgi'
require 'stringio'
require 'timeout'

def test_read_multipart_eof_fix
  boundary = '%?%(\w*)\\((\w*)\\)'
  data = "--#{boundary}\r\nContent-Disposition: form-data; name=\"a_field\"\r\n\r\nBang!\r\n--#{boundary}--\r\n"

  ENV['REQUEST_METHOD'] = "POST"
  ENV['CONTENT_TYPE']   = "multipart/form-data; boundary=\"#{boundary}\""
  ENV['CONTENT_LENGTH'] = data.length.to_s

  STDIN = StringIO.new(data)

  begin
    Timeout.timeout(3) { CGI.new }
    STDERR.puts ' => CGI is safe: read_multipart does not hang on malicious multipart requests.'
  rescue TimeoutError
    STDERR.puts ' => CGI is exploitable: read_multipart hangs on malicious multipart requests.'
  end
end

STDERR.puts 'Testing malicious multipart boundary request injection'
test_read_multipart_eof_fix

STDERR.puts 'Patching CGI::QueryExtension.read_multipart'
require 'rubygems'
require 'cgi_multipart_eof_fix'

test_read_multipart_eof_fix
