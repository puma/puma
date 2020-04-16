require "minitest"
require_relative "verbose_progress_plugin"

Minitest.load_plugins
Minitest.extensions << 'verbose_progress' unless Minitest.extensions.include?('verbose_progress')
