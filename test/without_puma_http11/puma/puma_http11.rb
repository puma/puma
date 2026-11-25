# frozen_string_literal: true

# Adding this directory to the load path hides Puma's puma_http11 extension,
# since Ruby finds this file before the compiled library.
raise LoadError, "puma_http11 is hidden by test/without_puma_http11"
