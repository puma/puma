# Security Policy

Thank you for helping to keep the internet secure. Please read this before making a security report.

## Supported Versions

We support the last two major versions and their latest minor.

| Version       | Supported  |
| :------------ | :--------: |
| Latest release in 8.x | ✅ |
| Latest release in 7.x | ✅ |
| All other releases    | ❌ |

## Our Threat Model

This determines what becomes a security advisory in Puma. We may make separate hardening fixes for things outside of this model.

### Who do we defend against?

1. **Anyone who can reach the app port** (the Unix, TCP or SSL bind that Puma serves the Rack app over). They can send any bytes, split up their data however they like, at any rate, with as many requests as they like on one connection or many. Their data is untrusted after in reaches your app. Puma must build the Rack `env` accurately and according to the Rack spec, and attacker controlled values in your return value of `app.call` must not break the HTTP response.
2. **Anyone who can watch or change encrypted network traffic between the `pumactl` utility and a Puma control server**. 
3. **Anyone who can reach Puma's control server without the control token.**

### Who do we trust?

We don't defend against someone who already controls:

- Puma's config, command-line flags, environment variables, Gemfile, or load path
- Any code running inside Puma, including your app, Rack middleware, plugins, and hooks
- Direct calls to Puma's Ruby code, such as building a parser by hand
- Local files and process setup: state files, PID files, signals, sockets passed in by systemd or a parent process, `key_password_command`, and `puma-wild`
- The control token
- A user account on the server (the actual host, not the Rack app). That account can reach Unix-socket control servers, state files, and logs.
- Your reverse proxies and load balancers, when configured correctly. We don't trust their forwarded requests.
- If you tell Puma to trust a header or the PROXY protocol, only your proxies should be able to reach Puma. 

### Bugs

Our features should work as designed. Bugs in our security features count in our threat model, even if they are optional. For example, if you turn on the optional control server and `pumactl` doesn't check a TLS certificate when it's supposed to, that's in scope.

### What's a Denial of Service?

If you throw enough traffic at _any_ web server, it eventually will fall over. So what's a DoS vulnerability in Puma?

* **A small effort in Puma can cause outsized harm to Puma or other users**, such as a process crash or restart.
* **The attack gets around a limit enforced by Puma**, such as timeout on how long a connection can be held.

### Request smuggling

When Puma and a proxy disagree about where one request ends and another begins, you can get a smuggling vuln. 

A smuggling report to Puma needs all three of these:

1. A real, popular, maintained proxy, set up in a realistic or valid way. Most reports to Puma fail this criterion because they propose hypothetical proxies which do not exist or would be doing something stupid. In that case, we might harden Puma against it, but it's not going to get an advisory from us.
2. A reproduction against that proxy.
3. Harm that crosses a security boundary, such as another user, cache, or connection shared with other users.

If Puma misreads an attacker's requests only for the attacker's own connection, that's not smuggling. We may fix it as a parser bug.

### How we triage

We ask:

1. Is it within the scope of our threat model?
2. What's the CVSS 4.0 score?

The answers can lead to the following outcomes:

* Out of scope. It's a real bug, but outside our threat model (e.g., an attacker who has to be able to read a state file). May still get a hardening fix.
* CVSS score is 0.0. No harm shown. No advisory. May get a hardening fix.
* Advisory. We fix and release with a GHSA or CVE. 

We don't publish advisories for unreleased code on main.

## Reporting a Vulnerability

[Report on Github](https://github.com/puma/puma/security).

AI reports are welcome.

Rejected out-scope reports can be filed as public issues or PRs, but we will probably do that for you.

If you include the following you will be more likely to help us:

1. Puma, Ruby, and OS versions, the config, a runnable reproduction, and for smuggling the proxy name, version and config.
