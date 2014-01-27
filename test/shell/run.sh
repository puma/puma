ERROR=0

if ruby -rubygems t1.rb > /dev/null 2>&1; then
  echo "t1 OK"
else
  echo "t1 FAIL"
  ERROR=1
fi

if ruby -rubygems t2.rb > /dev/null 2>&1; then
  echo "t2 OK"
else
  echo "t2 FAIL"
  ERROR=2
fi

if ruby -rubygems t3.rb > /dev/null 2>&1; then
  echo "t3 OK"
else
  echo "t3 FAIL"
  ERROR=3
fi

exit $ERROR
