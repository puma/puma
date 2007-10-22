# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'test/testhelp'

include Mongrel

class URIClassifierTest < Test::Unit::TestCase

  def test_uri_finding
    uri_classifier = URIClassifier.new
    uri_classifier.register("/test", 1)
    
    script_name, path_info, value = uri_classifier.resolve("/test")
    assert value
    assert_equal 1, value
    assert_equal "/test", script_name
  end


  def test_uri_prefix_ops
    test = "/pre/fix/test"
    prefix = "/pre"

    uri_classifier = URIClassifier.new
    uri_classifier.register(prefix,1)

    script_name, path_info, value = uri_classifier.resolve(prefix)
    script_name, path_info, value = uri_classifier.resolve(test)
    assert value
    assert_equal prefix, script_name
    assert_equal test[script_name.length .. -1], path_info

    assert uri_classifier.inspect
    assert_equal prefix, uri_classifier.uris[0]
  end

  def test_not_finding
    test = "/cant/find/me"
    uri_classifier = URIClassifier.new
    uri_classifier.register(test, 1)

    script_name, path_info, value = uri_classifier.resolve("/nope/not/here")
    assert_nil script_name
    assert_nil path_info
    assert_nil value
  end

  def test_exceptions
    uri_classifier = URIClassifier.new

    uri_classifier.register("/test", 1)
    
    failed = false
    begin 
      uri_classifier.register("/test", 1)
    rescue => e
      failed = true
    end

    assert failed

    failed = false
    begin
      uri_classifier.register("", 1)
    rescue => e
      failed = true
    end

    assert failed
  end


  def test_register_unregister
    uri_classifier = URIClassifier.new
    
    100.times do
      uri_classifier.register("/stuff", 1)
      value = uri_classifier.unregister("/stuff")
      assert_equal 1, value
    end

    uri_classifier.register("/things",1)
    script_name, path_info, value = uri_classifier.resolve("/things")
    assert_equal 1, value

    uri_classifier.unregister("/things")
    script_name, path_info, value = uri_classifier.resolve("/things")
    assert_nil value

  end


  def test_uri_branching
    uri_classifier = URIClassifier.new
    uri_classifier.register("/test", 1)
    uri_classifier.register("/test/this",2)
  
    script_name, path_info, handler = uri_classifier.resolve("/test")
    script_name, path_info, handler = uri_classifier.resolve("/test/that")
    assert_equal "/test", script_name, "failed to properly find script off branch portion of uri"
    assert_equal "/that", path_info
    assert_equal 1, handler, "wrong result for branching uri"
  end

  def test_all_prefixing
    tests = ["/test","/test/that","/test/this"]
    uri = "/test/this/that"
    uri_classifier = URIClassifier.new
    
    current = ""
    uri.each_byte do |c|
      current << c.chr
      uri_classifier.register(current, c)
    end
    

    # Try to resolve everything with no asserts as a fuzzing
    tests.each do |prefix|
      current = ""
      prefix.each_byte do |c|
        current << c.chr
        script_name, path_info, handler = uri_classifier.resolve(current)
        assert script_name
        assert path_info
        assert handler
      end
    end

    # Assert that we find stuff
    tests.each do |t|
      script_name, path_info, handler = uri_classifier.resolve(t)
      assert handler
    end

    # Assert we don't find stuff
    script_name, path_info, handler = uri_classifier.resolve("chicken")
    assert_nil handler
    assert_nil script_name
    assert_nil path_info
  end


  # Verifies that a root mounted ("/") handler resolves
  # such that path info matches the original URI.
  # This is needed to accommodate real usage of handlers.
  def test_root_mounted
    uri_classifier = URIClassifier.new
    root = "/"
    path = "/this/is/a/test"

    uri_classifier.register(root, 1)

    script_name, path_info, handler = uri_classifier.resolve(root)
    assert_equal 1, handler
    assert_equal root, path_info
    assert_equal root, script_name

    script_name, path_info, handler = uri_classifier.resolve(path)
    assert_equal path, path_info
    assert_equal root, script_name
    assert_equal 1, handler
  end

  # Verifies that a root mounted ("/") handler
  # is the default point, doesn't matter the order we use
  # to register the URIs
  def test_classifier_order
    tests = ["/before", "/way_past"]
    root = "/"
    path = "/path"

    uri_classifier = URIClassifier.new
    uri_classifier.register(path, 1)
    uri_classifier.register(root, 2)

    tests.each do |uri|
      script_name, path_info, handler = uri_classifier.resolve(uri)
      assert_equal root, script_name, "#{uri} did not resolve to #{root}"
      assert_equal uri, path_info
      assert_equal 2, handler
    end
  end
  
  def test_benchmark  
    @fragments = %w(the benchmark module provides methods to measure and report the time used to execute ruby code)

    @classifier = URIClassifier.new
    @classifier.register("/", 1)

    @requests = []
    
    @fragments.size.times do |n|
      this_uri = "/" + @fragments[0..n].join("/")
      @classifier.register(this_uri, 1)
      @requests << this_uri
    end
    
    @requests = @requests.map do |path|
      (0..100).map do |n|      
        path.size > n ? path[0..-n] : path
      end
    end.flatten * 10
    
    puts "#{@fragments.size} paths registered"
    puts "#{@requests.size} requests queued"
    
    Benchmark.bm do |x|
      x.report do
        @requests.each do |request|
          @classifier.resolve(request)
        end
      end
    end
    
  end
  
end

