
require 'test/unit'
require 'net/http'
require 'mongrel'

include Mongrel

class HttpParserTest < Test::Unit::TestCase
  def setup
    @h = HttpServer.new('127.0.0.1', 3501)
    @h.register('/', Mongrel::DirHandler.new('.'))
    @h.run
    
    @http = Net::HTTP.new(@h.host, @h.port)

    # get the ETag and Last-Modified headers
    @path = '/README'
    res = @http.start { |http| http.get(@path) }
    assert_not_nil @etag = res['ETag']
    assert_not_nil @last_modified = res['Last-Modified']
  end

  def teardown
    orig_stderr = STDERR.dup

    # temporarily disable the puts method in STDERR to silence warnings from stop
    class << STDERR
      define_method(:puts) {}
    end

    @h.stop
  ensure
    # restore STDERR
    STDERR.reopen(orig_stderr)
  end

  # status should be 304 Not Modified when If-None-Match is the matching ETag
  def test_not_modified_via_if_none_match
    assert_status_for_get_and_head Net::HTTPNotModified, 'If-None-Match' => @etag
  end

  # status should be 304 Not Modified when If-Unmodified-Since is the matching Last-Modified date
  def test_not_modified_via_if_unmodified_since
    assert_status_for_get_and_head Net::HTTPNotModified, 'If-Unmodified-Since' => @last_modified
  end

  # status should be 304 Not Modified when If-None-Match is the matching ETag
  # and If-Unmodified-Since is the matching Last-Modified date
  def test_not_modified_via_if_none_match_and_if_unmodified_since
    assert_status_for_get_and_head Net::HTTPNotModified, 'If-None-Match' => @etag, 'If-Unmodified-Since' => @last_modified
  end

  # status should be 200 OK when If-None-Match is invalid
  def test_invalid_if_none_match
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => 'invalid'
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => 'invalid', 'If-Unmodified-Since' => @last_modified
  end

  # status should be 200 OK when If-Unmodified-Since is invalid
  def test_invalid_if_unmodified_since
    assert_status_for_get_and_head Net::HTTPOK,                           'If-Unmodified-Since' => 'invalid'
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => @etag, 'If-Unmodified-Since' => 'invalid'
  end

  # status should be 304 Not Modified when If-Unmodified-Since is greater than the Last-Modified header, but less than the system time
  def test_if_unmodified_since_greater_than_last_modified
    sleep 2
    last_modified_plus_1 = (Time.httpdate(@last_modified) + 1).httpdate
    assert_status_for_get_and_head Net::HTTPNotModified,                           'If-Unmodified-Since' => last_modified_plus_1
    assert_status_for_get_and_head Net::HTTPNotModified, 'If-None-Match' => @etag, 'If-Unmodified-Since' => last_modified_plus_1
  end

  # status should be 200 OK when If-Unmodified-Since is less than the Last-Modified header
  def test_if_unmodified_since_less_than_last_modified
    last_modified_minus_1 = (Time.httpdate(@last_modified) - 1).httpdate
    assert_status_for_get_and_head Net::HTTPOK,                           'If-Unmodified-Since' => last_modified_minus_1
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => @etag, 'If-Unmodified-Since' => last_modified_minus_1
  end

  # status should be 200 OK when If-Unmodified-Since is a date in the future
  def test_future_if_unmodified_since
    the_future = Time.at(2**31-1).httpdate
    assert_status_for_get_and_head Net::HTTPOK,                           'If-Unmodified-Since' => the_future
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => @etag, 'If-Unmodified-Since' => the_future
  end

  # status should be 200 OK when If-None-Match is a wildcard
  def test_wildcard_match
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => '*'
    assert_status_for_get_and_head Net::HTTPOK, 'If-None-Match' => '*', 'If-Unmodified-Since' => @last_modified
  end

  private

    # assert the response status is correct for GET and HEAD
    def assert_status_for_get_and_head(status_class, headers = {})
      %w{ get head }.each do |method|
        res = @http.send(method, @path, headers)
        assert_kind_of status_class, res
        assert_equal @etag, res['ETag']
        case status_class
          when Net::HTTPNotModified : assert_nil res['Last-Modified']
          when Net::HTTPOK          : assert_equal @last_modified, res['Last-Modified']
        end
      end
    end
end
