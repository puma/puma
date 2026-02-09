if Puma.cli_config._options[:workers] == 2
  Puma.cli_config._options[:workers] = 4
end
