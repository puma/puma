'##################################################################
'# 
'# mongrel_service: Win32 native implementation for mongrel
'#                  (using ServiceFB and FreeBASIC)
'# 
'# Copyright (c) 2006 Multimedia systems
'# (c) and code by Luis Lavena
'# 
'#  mongrel_service (native) and mongrel_service gem_pluing are licensed
'#  in the same terms as mongrel, please review the mongrel license at
'#  http://mongrel.rubyforge.org/license.html
'#  
'##################################################################

'##################################################################
'# Requirements:
'# - FreeBASIC 0.17, Win32 CVS Build (as for November 09, 2006).
'# 
'##################################################################

#define SERVICEFB_INCLUDE_UTILS
#include once "lib/ServiceFB/ServiceFB.bi"
#include once "process.bi"

'# use for debug versions
#if not defined(GEM_VERSION)
  #define GEM_VERSION (debug mode)
#endif

'# preprocessor stringize
#define PPSTR(x) #x

namespace mongrel_service
    const VERSION as string = PPSTR(GEM_VERSION)
    
    '# namespace include
    using fb.svc
    using fb.svc.utils
    
    declare function single_onInit(byref as ServiceProcess) as integer
    declare sub single_onStart(byref as ServiceProcess)
    declare sub single_onStop(byref as ServiceProcess)
    
    '# SingleMongrel
    type SingleMongrel
        declare constructor()
        declare destructor()
        
        '# TODO: replace for inheritance here
        'declare function onInit() as integer
        'declare sub onStart()
        'declare sub onStop()
        
        __service       as ServiceProcess
        __child_pid     as uinteger
    end type
    
    '# TODO: replace with inheritance here
    dim shared single_mongrel_ref as SingleMongrel ptr
end namespace
