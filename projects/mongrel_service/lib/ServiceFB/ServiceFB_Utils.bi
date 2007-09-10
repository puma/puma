'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#if __FB_VERSION__ < "0.17"
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