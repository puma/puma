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

exit $ERROR
