wrk.method = "POST"
wrk.body   = string.rep("body", 1000000)
wrk.headers["content-type"] = "application/x-www-form-urlencoded"
