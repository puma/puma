module Puma

  # Every standard HTTP code mapped to the appropriate message.  These are
  # used so frequently that they are placed directly in Puma for easy
  # access rather than Puma::Const itself.
  HTTP_STATUS_CODES = {
    100  => 'Continue',
    101  => 'Switching Protocols',
    200  => 'OK',
    201  => 'Created',
    202  => 'Accepted',
    203  => 'Non-Authoritative Information',
    204  => 'No Content',
    205  => 'Reset Content',
    206  => 'Partial Content',
    300  => 'Multiple Choices',
    301  => 'Moved Permanently',
    302  => 'Moved Temporarily',
    303  => 'See Other',
    304  => 'Not Modified',
    305  => 'Use Proxy',
    400  => 'Bad Request',
    401  => 'Unauthorized',
    402  => 'Payment Required',
    403  => 'Forbidden',
    404  => 'Not Found',
    405  => 'Method Not Allowed',
    406  => 'Not Acceptable',
    407  => 'Proxy Authentication Required',
    408  => 'Request Time-out',
    409  => 'Conflict',
    410  => 'Gone',
    411  => 'Length Required',
    412  => 'Precondition Failed',
    413  => 'Request Entity Too Large',
    414  => 'Request-URI Too Large',
    415  => 'Unsupported Media Type',
    500  => 'Internal Server Error',
    501  => 'Not Implemented',
    502  => 'Bad Gateway',
    503  => 'Service Unavailable',
    504  => 'Gateway Time-out',
    505  => 'HTTP Version not supported'
  }

  # For some HTTP status codes the client only expects headers.
  STATUS_WITH_NO_ENTITY_BODY = {
    204 => true, 205 => true, 304 => true
  }

  # Frequently used constants when constructing requests or responses.  Many times
  # the constant just refers to a string with the same contents.  Using these constants
  # gave about a 3% to 10% performance improvement over using the strings directly.
  #
  # The constants are frozen because Hash#[]= when called with a String key dups
  # the String UNLESS the String is frozen. This saves us therefore 2 object
  # allocations when creating the env hash later.
  #
  # While Puma does try to emulate the CGI/1.2 protocol, it does not use the REMOTE_IDENT,
  # REMOTE_USER, or REMOTE_HOST parameters since those are either a security problem or
  # too taxing on performance.
  module Const

    # The default number of seconds for another request within a persistent
    # session.
    PERSISTENT_TIMEOUT = 20

    DATE = "Date".freeze

    SCRIPT_NAME = "SCRIPT_NAME".freeze

    # The original URI requested by the client.
    REQUEST_URI= 'REQUEST_URI'.freeze
    REQUEST_PATH = 'REQUEST_PATH'.freeze

    PATH_INFO = 'PATH_INFO'.freeze

    PUMA_VERSION = VERSION = "1.1.1".freeze

    PUMA_TMP_BASE = "puma".freeze

    # The standard empty 404 response for bad requests.  Use Error4040Handler for custom stuff.
    ERROR_404_RESPONSE = "HTTP/1.1 404 Not Found\r\nConnection: close\r\nServer: Puma #{PUMA_VERSION}\r\n\r\nNOT FOUND".freeze

    CONTENT_LENGTH = "CONTENT_LENGTH".freeze

    # A common header for indicating the server is too busy.  Not used yet.
    ERROR_503_RESPONSE = "HTTP/1.1 503 Service Unavailable\r\n\r\nBUSY".freeze

    # The basic max request size we'll try to read.
    CHUNK_SIZE = 16 * 1024

    # This is the maximum header that is allowed before a client is booted.  The parser detects
    # this, but we'd also like to do this as well.
    MAX_HEADER = 1024 * (80 + 32)

    # Maximum request body size before it is moved out of memory and into a tempfile for reading.
    MAX_BODY = MAX_HEADER

    # A frozen format for this is about 15% faster
    STATUS_FORMAT = "HTTP/1.1 %d %s\r\nConnection: close\r\n".freeze

    CONTENT_TYPE = "Content-Type".freeze

    LAST_MODIFIED = "Last-Modified".freeze
    ETAG = "ETag".freeze
    SLASH = "/".freeze
    REQUEST_METHOD = "REQUEST_METHOD".freeze
    GET = "GET".freeze
    HEAD = "HEAD".freeze
    # ETag is based on the apache standard of hex mtime-size-inode (inode is 0 on win32)
    ETAG_FORMAT = "\"%x-%x-%x\"".freeze
    LINE_END = "\r\n".freeze
    REMOTE_ADDR = "REMOTE_ADDR".freeze
    HTTP_X_FORWARDED_FOR = "HTTP_X_FORWARDED_FOR".freeze
    HTTP_IF_MODIFIED_SINCE = "HTTP_IF_MODIFIED_SINCE".freeze
    HTTP_IF_NONE_MATCH = "HTTP_IF_NONE_MATCH".freeze
    REDIRECT = "HTTP/1.1 302 Found\r\nLocation: %s\r\nConnection: close\r\n\r\n".freeze
    HOST = "HOST".freeze

    SERVER_NAME = "SERVER_NAME".freeze
    SERVER_PORT = "SERVER_PORT".freeze
    HTTP_HOST = "HTTP_HOST".freeze
    PORT_80 = "80".freeze

    SERVER_PROTOCOL = "SERVER_PROTOCOL".freeze
    HTTP_11 = "HTTP/1.1".freeze
    HTTP_10 = "HTTP/1.0".freeze

    SERVER_SOFTWARE = "SERVER_SOFTWARE".freeze
    GATEWAY_INTERFACE = "GATEWAY_INTERFACE".freeze
    CGI_VER = "CGI/1.2".freeze

    STOP_COMMAND = "?".freeze
    HALT_COMMAND = "!".freeze

    RACK_INPUT = "rack.input".freeze
    RACK_URL_SCHEME = "rack.url_scheme".freeze
    RACK_AFTER_REPLY = "rack.after_reply".freeze

    HTTP = "http".freeze
    HTTPS = "https".freeze

    HTTPS_KEY = "HTTPS".freeze

    HTTP_VERSION = "HTTP_VERSION".freeze
    HTTP_CONNECTION = "HTTP_CONNECTION".freeze

    HTTP_11_200 = "HTTP/1.1 200 OK\r\n".freeze
    HTTP_10_200 = "HTTP/1.0 200 OK\r\n".freeze

    CLOSE = "close".freeze
    KEEP_ALIVE = "Keep-Alive".freeze

    CONTENT_LENGTH2 = "Content-Length".freeze
    CONTENT_LENGTH_S = "Content-Length: ".freeze
    TRANSFER_ENCODING = "Transfer-Encoding".freeze

    CONNECTION_CLOSE = "Connection: close\r\n".freeze
    CONNECTION_KEEP_ALIVE = "Connection: Keep-Alive\r\n".freeze

    TRANSFER_ENCODING_CHUNKED = "Transfer-Encoding: chunked\r\n".freeze
    CLOSE_CHUNKED = "0\r\n\r\n".freeze

    COLON = ": ".freeze

    NEWLINE = "\n".freeze
  end
end
