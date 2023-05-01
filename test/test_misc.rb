require_relative "helper"
require 'open3'

class TestMisc < Minitest::Test
  parallelize_me! if ::Puma::IS_MRI

  def test_puma_response_server_header_value_empty
    responses, _, status = Open3.capture3(
      'ruby -rbundler/setup -r./test/helpers/request_server_header -e "SetReqServerHeader.no_set_header"'
    )
    sleep 0.1 until status.success?
    assert_includes responses, 'HTTP/1.1'
    refute_includes responses, 'Puma'
  end

  def test_puma_response_server_header_value_set
    responses, _, status = Open3.capture3(
      'ruby -rbundler/setup -r./test/helpers/request_server_header -e "SetReqServerHeader.set_header"'
    )
    sleep 0.1 until status.success?
    assert_includes responses, 'HTTP/1.1'
    assert_includes responses, 'Puma 6.2.2'
  end
end
