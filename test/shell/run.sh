if ruby t1.rb > /dev/null 2>&1; then
  echo "t1 OK"
  exit 0
else
  echo "t1 FAIL"
  exit 1
fi
