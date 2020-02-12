wrk.method = "POST"
wrk.body   = string.rep("body", 1000000)
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"
