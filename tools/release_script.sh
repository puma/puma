#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "release_script/app"

ReleaseScript::App.new(ARGV, env: ENV).run
