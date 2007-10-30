require 'mkmf'

dir_config("uri_classifier")
have_library("c", "main")
create_makefile("uri_classifier")
