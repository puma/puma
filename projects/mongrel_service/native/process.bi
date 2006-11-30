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

#ifndef __Process_bi__
#define __Process_bi__

#include once "windows.bi"

namespace fb
namespace process
    '# fb.process functions that allow creation/graceful termination
    '# of child process.
    
    '# Process Status Enum
    enum ProcessStateEnum
        ProcessQueryError = 0
        ProcessStillActive = STILL_ACTIVE
    end enum
    
    
    '# Spawn(cmdline) will try to create a new process, monitor
    '# if it launched successfuly (5 seconds) and then return the
    '# new children PID (Process IDentification) or 0 in case of problems
    declare function Spawn(byref as string) as uinteger
    
    '# Terminate(PID) will hook the special console handler (_child_console_handler)
    '# and try sending CTRL_C_EVENT, CTRL_BREAK_EVENT and TerminateProcess
    '# in case of the first two fails.
    declare function Terminate(byval as uinteger) as BOOL
    
    '# StillActive(PID) will return FALSE (0) in case the process no longer
    '# exist of get terminated with error.
    declare function Status(byval as uinteger) as ProcessStateEnum
    
    '# Special hook used to avoid the process calling Terminate()
    '# respond to CTRL_*_EVENTS when terminating child process
    declare function _child_console_handler(byval as DWORD) as BOOL
end namespace '# fb.process
end namespace '# fb

#endif '# __Process_bi__
