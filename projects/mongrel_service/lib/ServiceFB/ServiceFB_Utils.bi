'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# Permission is hereby granted, free of charge, to any person obtaining
'# a copy of this software and associated documentation files (the
'# "Software"), to deal in the Software without restriction, including
'# without limitation the rights to use, copy, modify, merge, publish,
'# distribute, sublicense, and/or sell copies of the Software, and to
'# permit persons to whom the Software is furnished to do so, subject to
'# the following conditions:
'#
'# The above copyright notice and this permission notice shall be
'# included in all copies or substantial portions of the Software.
'#
'# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
'# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
'# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
'# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
'# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
'# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
'# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
'#++

#if __FB_VERSION__ <> "0.17"
#error ServiceFB is designed to compile with FreeBASIC version "0.17"
#else

#ifndef __FB_WIN32__
#error Platform unsupported. Compiling ServiceFB requires Windows platform.
#else

#ifndef __ServiceFB_Utils_bi__
#define __ServiceFB_Utils_bi__

#include once "win/psapi.bi"
#include once "win/tlhelp32.bi"

namespace fb
namespace svc
namespace utils   '# fb.svc.utils
    '# use this to determine (using select case maybe?) the
    '# mode which the service was invoked.
    enum ServiceRunMode
        RunAsUnknown = 0
        RunAsService
        RunAsManager
        RunAsConsole
    end enum
    
    
    '# ServiceController type (object)
    '# this is a helper object in case you want to implement
    '# console mode (command line testing/debugging) and management (install/remove/control)
    '# to your services, all from the same executable
    type ServiceController
        '# ctor/dtor()
        declare constructor()
        declare constructor(byref as string)
        declare constructor(byref as string, byref as string)
        declare constructor(byref as string, byref as string, byref as string)
        declare destructor()
        
        '# methods (public)
        declare sub Banner()
        declare function RunMode() as ServiceRunMode
        declare sub Manage()
        declare sub Manage(byref as ServiceProcess)
        declare sub Console()
        declare sub Console(byref as ServiceProcess)
        
        '# properties (public)
        '# use these properties for shwoing information on console/manager mode
        '# as banner.
        '# Product, version
        '# copyright
        product     as string
        version     as string
        copyright   as string
    end type
end namespace     '# fb.svc.utils
end namespace     '# fb.svc
end namespace     '# fb

#endif '# __ServiceFB_bi__
#endif '# __FB_WIN32__
#endif '# __FB_VERSION__