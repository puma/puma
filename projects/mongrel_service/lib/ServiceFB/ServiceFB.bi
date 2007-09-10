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

#ifndef __ServiceFB_bi__
#define __ServiceFB_bi__

#include once "windows.bi"
#inclib "advapi32"

namespace fb
namespace svc   '# fb.svc
#ifdef SERVICEFB_DEBUG_LOG
    '# debug print
    declare sub _dprint(byref as string)
#else
    #define _dprint(message)
#endif
    
    '# service states used by end user with 'state' property
    enum ServiceStateEnum
        Running = SERVICE_RUNNING
        Paused = SERVICE_PAUSED
        Stopped = SERVICE_STOPPED
    end enum
    
    
    '# ServiceProcess type (object)
    '# use this to create new services and reference the on*() methods to perform the related
    '# tasks.
    type ServiceProcess
        '# ctor/dtor
        declare constructor()
        declare constructor(byref as string)
        declare destructor()
        
        '# methods (public)
        declare sub Run()
        declare sub StillAlive(byval as integer = 10)
        
        '# helper methods (private)
        declare sub UpdateState(byval as DWORD, byval as integer = 0, byval as integer = 0)
        
        '# pseudo-events
        '# for onInit you should return FALSE (0) in case you want to abort
        '# service initialization.
        '# If everything was ok, then return TRUE (-1)
        onInit          as function(byref as ServiceProcess) as integer
        onStart         as sub(byref as ServiceProcess)
        onStop          as sub(byref as ServiceProcess)
        onPause         as sub(byref as ServiceProcess)
        onContinue      as sub(byref as ServiceProcess)
        
        '# call_* are used to avoid the warning arround ThreadCreate
        declare static sub call_onStart(byval as any ptr)
        
        '# properties (public)
        name            as string
        description     as string
        state           as ServiceStateEnum
        commandline     as string                   '# TODO
        shared_process  as integer
        
        '# properties (private)
        _svcStatus      as SERVICE_STATUS
        _svcHandle      as SERVICE_STATUS_HANDLE
        _svcStopEvent   as HANDLE
        _threadHandle   as any ptr
    end type
    
    
    '# ServiceHost type (object)
    '# use this, beside ServiceProcess, to manage the registration and running of
    '# several services sharing the same process.
    '# NOTE: ServiceHost.Run() and ServiceProcess.Run() are mutually exclusive, that
    '# means don't mix single service with multiple service in the same program!
    type ServiceHost
        '# ctor/dtor()
        declare constructor()
        declare destructor()
        
        '# methods (public)
        declare sub Add(byref as ServiceProcess)
        declare sub Run()
        
        '# properties (public)
        count           as integer
    end type
end namespace   '# fb.svc
end namespace   '# fb

#ifdef SERVICEFB_INCLUDE_UTILS
#include once "ServiceFB_Utils.bi"
#endif

#endif '# __ServiceFB_bi__
#endif '# __FB_WIN32__
#endif '# __FB_VERSION__