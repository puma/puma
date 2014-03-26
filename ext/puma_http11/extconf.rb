require 'mkmf'

dir_config("puma_http11")

$defs.push "-Wno-deprecated-declarations"
$DLDFLAGS.delete "-multiply_definedsuppress"
$libs += " -lssl -lcrypto "

create_makefile("puma/puma_http11")
