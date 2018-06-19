# PowerShell script setting base variables for EventMachine fat binary gem
# Code by MSP-Greg, see https://github.com/MSP-Greg/appveyor-utilities

# load utility functions, pass 64 or 32
. $PSScriptRoot\shared\appveyor_setup.ps1 $args[0]

# above is required code
#———————————————————————————————————————————————————————————————— above for all repos

Make-Const gem_name  'puma'
Make-Const repo_name 'puma'
Make-Const url_repo  'https://github.com/puma/puma.git'

#———————————————————————————————————————————————————————————————— lowest ruby version
Make-Const ruby_vers_low 22

#———————————————————————————————————————————————————————————————— make info
Make-Const dest_so   'lib\puma'
Make-Const exts      @(
  @{ 'conf' = 'ext/puma_http11/extconf.rb' ; 'so' = 'puma_http11' }
)
Make-Const write_so_require $true

#———————————————————————————————————————————————————————————————— pre compile
# runs before compiling starts on every ruby version
function Pre-Compile {
  # load the correct OpenSSL version in the build system
  Check-OpenSSL
  Write-Host Compiling With $env:SSL_VERS
}

#———————————————————————————————————————————————————————————————— Run-Tests
function Run-Tests {
  # call with comma separated list of gems to install or update
  Update-Gems minitest, minitest-retry, rack, rake
  $env:CI = 1
  rake -f Rakefile_wintest -N -R norakelib | Set-Content -Path $log_name -PassThru -Encoding UTF8
  minitest  # collects test results

}

#———————————————————————————————————————————————————————————————— below for all repos
# below is required code
Make-Const dir_gem  $(Convert-Path $PSScriptRoot\..)
Make-Const dir_ps   $PSScriptRoot

Push-Location $PSScriptRoot
.\shared\make.ps1
.\shared\test.ps1
Pop-Location

exit $ttl_errors_fails + $exit_code
