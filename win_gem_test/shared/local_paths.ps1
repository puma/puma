# Ruby version to use for none version specfic code, also where $SSL_CERT_FILE
# should be located
Make-Const dflt_ruby 'C:\Greg\ruby25-x64'
Make-Const in_av     $false

# MinGW & Base Ruby
Make-Const msys2     'C:\Greg\msys64'
Make-Const dir_ruby  'C:\Greg\Ruby'

# DevKit paths, windows & unix style, windows prefixed for 7z
Make-Const DK32w     'C:\Greg\DevKit'
Make-Const DK64w     'C:\Greg\DevKit-x64'

# Folder for storing downloaded packages
Make-Const pkgs      'C:\Greg\packages'

# Base path for local use
Make-Const base_path 'C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;C:\Program Files\Intel\iCLS Client\;C:\Program Files (x86)\Intel\iCLS Client\;C:\Program Files (x86)\Intel\Intel(R) Management Engine Components\DAL;C:\Program Files\Intel\Intel(R) Management Engine Components\DAL;C:\Program Files (x86)\Intel\Intel(R) Management Engine Components\IPT;C:\Program Files\Intel\Intel(R) Management Engine Components\IPT;C:\Program Files\Git\cmd;'

Make-Const 7z        "$env:ProgramFiles\7-Zip\7z.exe"
Make-Const fc        'Yellow'
