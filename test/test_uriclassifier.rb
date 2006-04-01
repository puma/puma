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

    sn,pi,val = u.resolve(prefix)
    sn,pi,val = u.resolve(test)
    assert val != nil, "didn't resolve"
    assert_equal prefix,sn, "wrong script name"
    assert_equal test[sn.length .. -1],pi, "wrong path info"

    assert u.inspect != nil, "No inspect for classifier"
    assert u.uris[0] == prefix, "URI list didn't match"
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


  def test_uri_branching
    u = URIClassifier.new
    u.register("/test", 1)
    u.register("/test/this",2)
  
    sn,pi,h = u.resolve("/test")
    sn,pi,h = u.resolve("/test/that")
    assert_equal "/test", sn, "failed to properly find script off branch portion of uri"
    assert_equal "/that", pi, "didn't get the right patch info"
    assert_equal 1, h, "wrong result for branching uri"
  end

  def test_all_prefixing
    tests = ["/test","/test/that","/test/this"]
    uri = "/test/this/that"
    u = URIClassifier.new
    
    cur = ""
    uri.each_byte do |c|
      cur << c.chr
      u.register(cur, c)
    end

    # try to resolve everything with no asserts as a fuzzing
    tests.each do |prefix|
      cur = ""
      prefix.each_byte do |c|
        cur << c.chr
        sn, pi, h = u.resolve(cur)
        assert sn != nil, "didn't get a script name"
        assert pi != nil, "didn't get path info"
        assert h != nil, "didn't find the handler"
      end
    end

    # assert that we find stuff
    tests.each do |t|
      sn, pi, h = u.resolve(t)
      assert h != nil, "didn't find handler"
    end

    # assert we don't find stuff
    sn, pi, h = u.resolve("chicken")
    assert_nil h, "shoulnd't find anything"
    assert_nil sn, "shoulnd't find anything"
    assert_nil pi, "shoulnd't find anything"
  end


  # Verifies that a root mounted ("/") handler resolves
  # such that path info matches the original URI.
  # This is needed to accomodate real usage of handlers.
  def test_root_mounted
    u = URIClassifier.new
    root = "/"
    path = "/this/is/a/test"

    u.register(root, 1)

    sn, pi, h = u.resolve(root)
    assert_equal 1,h, "didn't find handler"
    assert_equal root,pi, "didn't get right path info"
    assert_equal root,sn, "didn't get right script name"

    sn, pi, h = u.resolve(path)
    assert_equal path,pi, "didn't get right path info"
    assert_equal root,sn, "didn't get right script name"
    assert_equal 1,h, "didn't find handler"
  end


end

