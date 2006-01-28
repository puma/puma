require 'test/unit'
require 'net/http'
require 'mongrel'
require 'benchmark'

include Mongrel

class URIClassifierTest < Test::Unit::TestCase

  def test_uri_finding
    u = URIClassifier.new
    u.register("/test", 1)
    
    sn,pi,val = u.resolve("/test")
    assert val != nil, "didn't resolve"
    assert_equal 1, val, "wrong value"
    assert_equal "/test",sn, "wrong SCRIPT_NAME"
  end


  def test_uri_prefix_ops
    test = "/pre/fix/test"
    prefix = "/pre"

    u = URIClassifier.new
    u.register(prefix,1)

    sn,pi,val = u.resolve(test)
    assert val != nil, "didn't resolve"
    assert_equal prefix,sn, "wrong script name"
    assert_equal test[sn.length .. -1],pi, "wrong path info"
  end

  def test_not_finding
    test = "/cant/find/me"
    u = URIClassifier.new
    u.register(test, 1)

    sn,pi,val = u.resolve("/nope/not/here")
    assert_equal nil,sn, "shouldn't be found"
    assert_equal nil,pi, "shouldn't be found"
    assert_equal nil,val, "shouldn't be found"
  end

  def test_exceptions
    u = URIClassifier.new

    u.register("test", 1)
    
    failed = false
    begin 
      u.register("test", 1)
    rescue => e
      failed = true
    end

    assert failed, "it didn't fail as expected"

    failed = false
    begin
      u.register("", 1)
    rescue => e
      failed = true
    end

    assert failed, "it didn't fail as expected"
  end


  def test_register_unregister
    u = URIClassifier.new
    
    100.times do
      u.register("stuff", 1)
      val = u.unregister("stuff")
      assert_equal 1,val, "didn't get the right return value"
    end

    u.register("things",1)
    sn,pi,val = u.resolve("things")
    assert_equal 1, val, "result doesn't match"

    u.unregister("things")
    sn,pi,val = u.resolve("things")
    assert_equal nil, val, "result should be nil"

  end


  def test_performance
    count = 8500
    u = URIClassifier.new
    u.register("stuff",1)

    res = Benchmark.measure {   count.times { u.resolve("stuff") } }
    
    reg_unreg = Benchmark.measure { count.times { u.register("other",1); u.unregister("other"); } }

    puts "\nRESOLVE(#{count}): #{res}"
    puts "REG_UNREG(#{count}): #{reg_unreg}"
  end
      
end

