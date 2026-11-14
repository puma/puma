# Configuration

## Configuration File

You can also provide a configuration file with the `-C` (or `--config`) flag:

```
$ puma -C /path/to/config
```

If no configuration file is specified, Puma will look for a configuration file at `config/puma.rb`. If an environment is specified (via the `--environment` flag or through the `APP_ENV`, `RACK_ENV`, or `RAILS_ENV` environment variables) Puma looks for a configuration file at `config/puma/<environment_name>.rb` and then falls back to `config/puma.rb`.

If you want to prevent Puma from looking for a configuration file in those locations, include the `--no-config` flag:

```
$ puma --no-config

# or

$ puma -C "-"
```

The other side-effects of setting the environment are whether to show stack traces (in `development` or `test`), and setting RACK_ENV may potentially affect middleware looking for this value to change their behavior. The default puma RACK_ENV value is `development`. You can see all config default values in `Puma::Configuration#puma_default_options` or [configuration.rb](https://github.com/puma/puma/blob/61c6213fbab/lib/puma/configuration.rb#L182-L204).

## Thread Pool

Puma uses a thread pool. You can set the minimum and maximum number of threads that are available in the pool with the `-t` (or `--threads`) flag:

```
$ puma -t 8:32
```

Puma will automatically scale the number of threads, from the minimum until it caps out at the maximum, based on how much traffic is present. The current default is `0:16` and on MRI is `0:5`. Feel free to experiment, but be careful not to set the number of maximum threads to a large number, as you may exhaust resources on the system (or cause contention for the Global VM Lock, when using MRI).

Be aware that additionally Puma creates threads on its own for internal purposes (e.g. handling slow clients). So, even if you specify -t 1:1, expect around 7 threads created in your application.

## Master process lifecycle hooks

Puma's configuration DSL provides master process lifecycle hooks `after_booted`, `before_restart`, and `after_stopped`
which may be used to specify code blocks to run on each event:

```ruby
# config/puma.rb
after_booted do
  # Add code to run in the Puma master process after it boots,
  # and also after a phased restart completes.
end

before_restart do
  # Add code to run in the Puma master process when it receives
  # a restart command but before it restarts.
end

after_stopped do
  # Add code to run in the Puma master process after outstanding
  # requests have finished and Puma has stopped.
end
```

## Error handling

If Puma encounters an error outside of the context of your application, it will respond with a 400/500 and a simple
textual error message (see `Puma::Server#lowlevel_error` or [server.rb](https://github.com/puma/puma/blob/main/lib/puma/server.rb)).
You can specify custom behavior for this scenario. For example, you can report the error to your third-party
error-tracking service (in this example, [rollbar](https://rollbar.com)):

```ruby
lowlevel_error_handler do |e, env, status|
  if status == 400
    message = "The server could not process the request due to an error, such as an incorrectly typed URL, malformed syntax, or a URL that contains illegal characters.\n"
  else
    message = "An error has occurred, and engineers have been informed. Please reload the page. If you continue to have problems, contact support@example.com\n"
    Rollbar.critical(e)
  end

  [status, {}, [message]]
end
```
