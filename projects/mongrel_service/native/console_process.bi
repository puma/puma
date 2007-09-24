'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#ifndef __CONSOLE_PROCESS_BI__
#define __CONSOLE_PROCESS_BI__

#include once "windows.bi"
#include once "boolean.bi"

enum ProcessStdEnum
    ProcessStdOut   = 1 
    ProcessStdErr   = 2
    ProcessStdBoth  = 3
end enum

type ConsoleProcess
    '# this class provide basic functionality
    '# to control child processes
    
    '# new ConsoleProcess(Filename, Parameters)
    declare constructor(byref as string = "", byref as string = "")
    
    '# delete
    declare destructor()
    
    '# properties (only getters)
    declare property filename as string
    declare property filename(byref as string)
    
    declare property arguments as string
    declare property arguments(byref as string)
    
    '# stdout and stderr allow you redirect
    '# console output and errors to files
    declare property redirected_stdout as string
    declare property redirected_stderr as string
    
    '# evaluate if the process is running
    declare property running as boolean
    
    '# pid will return the current Process ID, or 0 if no process is running
    declare property pid as uinteger
    
    '# exit_code is the value set by the process prior exiting.
    declare property exit_code as uinteger
    
    '# methods
    declare function redirect(byval as ProcessStdEnum, byref as string) as boolean
    declare function start() as boolean
    declare function terminate(byval as boolean = false) as boolean
    
    private:
        _filename as string
        _arguments as string
        _pid as uinteger
        _process_info as PROCESS_INFORMATION
        _show_console as boolean = false
        
        _redirect_stdout as boolean
        _stdout_filename as string
        
        _redirect_stderr as boolean
        _stderr_filename as string
        
        '# this fake console handler
        '# is used to trap ctrl-c
        declare static function _console_handler(byval as DWORD) as BOOL
        
end type 'ConsoleProcess

#endif '__CONSOLE_PROCESS_BI__
