require 'puma'

# This file is just used with two tests in test/test_misc.rb.  Both tests check
# setting the `Puma::Client::ERROR_RESPONSE` constant in `::Puma::Server.new`.
#
module SetReqServerHeader
  APP = ->(env) { [200, {}, []] }

  class << self

    # Used to check if the constant is properly defined without
    # a `Server:` header
    def no_set_header
      svr = ::Puma::Server.new APP
      STDOUT.syswrite ::Puma::Client::ERROR_RESPONSE.values.join
    end

    # Used to check if the constant is properly defined when a `Server:` header
    # is defined using `Puma::DSL#server_header_value`
    def set_header
      svr = ::Puma::Server.new APP, nil, {puma_server_header_value: 'Puma 6.2.2'}
      STDOUT.syswrite ::Puma::Client::ERROR_RESPONSE.values.join
    end
  end
end
