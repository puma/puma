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

#include once "process.bi"
#define DEBUG_LOG_FILE EXEPATH + "\mongrel_service.log"
#include once "_debug.bi"

namespace fb
namespace process
    '# Spawn(cmdline) will try to create a new process, monitor
    '# if it launched successfuly (5 seconds) and then return the
    '# new children PID (Process IDentification) or 0 in case of problems
    function Spawn(byref cmdline as string) as uinteger
        dim result as uinteger
        dim success as BOOL
        
        '# New Process resources
        dim child as PROCESS_INFORMATION
        dim context as STARTUPINFO
        dim child_sa as SECURITY_ATTRIBUTES = type(sizeof(SECURITY_ATTRIBUTES), NULL, TRUE)
        dim wait_code as DWORD
        
        '# StdIn, StdOut, StdErr Read and Write Pipes.
        dim as HANDLE StdInRd, StdOutRd, StdErrRd
        dim as HANDLE StdInWr, StdOutWr, StdErrWr
        
        debug("Spawn() init")
        
        '# to ensure everything will work, we must allocate a console
        '# using AllocConsole, even if it fails.
        '# This solve the problems when running as service.
        if (AllocConsole() = 0) then
            debug("Success in AllocConsole()")
        else
            debug("AllocConsole failed, maybe already allocated, safely to discart.")
        end if
        
        '# presume all worked
        success = TRUE
        
        '# Create the pipes
        '# StdIn
        if (CreatePipe( @StdInRd, @StdInWr, @child_sa, 0 ) = 0) then
            debug("Error creating StdIn pipes.")
            success = FALSE
        end if
        
        '# StdOut
        if (CreatePipe( @StdOutRd, @StdOutWr, @child_sa, 0 ) = 0) then
            debug("Error creating StdOut pipes.")
            success = FALSE
        end if
        
        '# StdErr
        if (CreatePipe( @StdErrRd, @StdErrWr, @child_sa, 0 ) = 0) then
            debug("Error creating StdErr pipes.")
            success = FALSE
        end if
        
        '# Ensure the handles to the pipe are not inherited.
        if (SetHandleInformation( StdInWr, HANDLE_FLAG_INHERIT, 0) = 0) then
            debug("Error disabling StdInWr handle.")
            success = FALSE
        end if
        
        if (SetHandleInformation( StdOutRd, HANDLE_FLAG_INHERIT, 0) = 0) then
            debug("Error disabling StdOutRd handle.")
            success = FALSE
        end if
        
        if (SetHandleInformation( StdErrRd, HANDLE_FLAG_INHERIT, 0) = 0) then
            debug("Error disabling StdErrRd handle.")
            success = FALSE
        end if
        
        '# without the pipes, we shouldn't continue!
        if (success = TRUE) then
            '# Set the Std* handles ;-)
            with context
                .cb = sizeof( context )
                .hStdError = StdErrWr
                .hStdOutput = StdOutWr
                .hStdInput = StdInRd
                .dwFlags = STARTF_USESTDHANDLES
            end with
            
            '# now creates the process
            debug("Creating child process with cmdline: " + cmdline)
            if (CreateProcess(NULL, _
                                strptr(cmdline), _
                                NULL, _
                                NULL, _
                                TRUE, _
                                0, _
                                NULL, _
                                NULL, _
                                @context, _
                                @child) = 0) then
                
                debug("Error creating child process, error #" + str(GetLastError()))
                result = 0
            else
                '# close the Std* handles
                debug("Closing handles.")
                CloseHandle(StdInRd)
                CloseHandle(StdInWr)
                CloseHandle(StdOutRd)
                CloseHandle(StdOutWr)
                CloseHandle(StdErrRd)
                CloseHandle(StdErrWr)
                
                '# close children main Thread handle
                if (CloseHandle(child.hThread) = 0) then
                    debug("Problem closing children main thread.")
                end if
                
                '# now wait 2 seconds if the children process unexpectly quits
                wait_code = WaitForSingleObject(child.hProcess, 2000)
                debug("wait_code: " + str(wait_code))
                if (wait_code = WAIT_TIMEOUT) then
                    '# the process is still running, we are good
                    '# save a reference to the pid
                    result = child.dwProcessId
                    debug("New children PID: " + str(result))
                    
                    '# now close the handle
                    CloseHandle(child.hProcess)
                else
                    '# the process failed or terminated earlier
                    debug("failed, the process terminate earlier.")
                    result = 0
                end if '# (wait_code = WAIT_OBJECT_0)
            end if '# (CreateProcess() = 0)
        else
            debug("problem preparing environment for child process, no success")
            result = 0
        end if '# (success = TRUE)
        
        debug("Spawn() done")
        return result
    end function
    
    
    '# Terminate(PID) will hook the special console handler (_child_console_handler)
    '# and try sending CTRL_C_EVENT, CTRL_BREAK_EVENT and TerminateProcess
    '# in case of the first two fails.
    function Terminate(pid as uinteger) as BOOL
        dim result as BOOL
        dim success as BOOL
        dim exit_code as DWORD
        dim wait_code as DWORD
        
        '# process resources
        dim child as HANDLE
        
        debug("Terminate() init")
        
        '# is pid valid?
        if (pid > 0) then
            '# hook our custom console handler
            debug("hooking console handler")
            if (SetConsoleCtrlHandler(@_child_console_handler, TRUE) = 0) then
                debug("error hooking our custom error handler")
            end if
            
            '# get a handle to Process
            debug("OpenProcess() with Terminate and Query flags")
            child = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_TERMINATE or SYNCHRONIZE, FALSE, pid)
            if not (child = NULL) then
                '# process is valid, perform actions
                success = FALSE
                
                '# send CTRL_C_EVENT and wait for result
                debug("sending Ctrl-C to child pid " + str(pid))
                if not (GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) = 0) then
                    '# it worked, wait 5 seconds terminates.
                    debug("send worked, waiting 5 seconds to terminate...")
                    wait_code = WaitForSingleObject(child, 5000)
                    debug("wait_code: " + str(wait_code))
                    if not (wait_code = WAIT_TIMEOUT) then
                        debug("child process terminated properly.")
                        success = TRUE
                    end if
                else
                    debug("cannot generate event, error " + str(GetLastError()))
                    success = FALSE
                end if
                
                '# Ctrl-C didn't work, try Ctrl-Break
                if (success = FALSE) then
                    '# send CTRL_BREAK_EVENT and wait for result
                    debug("sending Ctrl-Break to child pid " + str(pid))
                    if not (GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0) = 0) then
                        '# it worked, wait 5 seconds terminates.
                        debug("send worked, waiting 5 seconds to terminate...")
                        wait_code = WaitForSingleObject(child, 5000) 
                        debug("wait_code: " + str(wait_code))
                        if not (wait_code = WAIT_TIMEOUT) then
                            debug("child process terminated properly.")
                            success = TRUE
                        end if
                    else
                        debug("cannot generate event, error " + str(GetLastError()))
                        success = FALSE
                    end if
                end if
                
                '# still no luck? we should do a hard kill then
                if (success = FALSE) then
                    debug("doing kill using TerminateProcess")
                    if (TerminateProcess(child, 3) = 0) then
                        debug("TerminateProcess failed, error " + str(GetLastError()))
                    else
                        success = TRUE
                    end if
                end if
                
                '# now get process exit code
                if not (GetExitCodeProcess(child, @exit_code) = 0) then
                    debug("getting child process exit code: " + str(exit_code))
                    if (exit_code = 0) then
                        debug("process terminated ok.")
                        result = TRUE
                    elseif (exit_code = STILL_ACTIVE) then
                        debug("process still active")
                        result = FALSE
                    else
                        debug("process terminated with exit_code: " + str(exit_code))
                        result = TRUE
                    end if
                else
                    debug("error getting child process exit code, value: " + str(exit_code) + ", error " + str(GetLastError()))
                    result = FALSE
                end if
            else
                '# invalid process handler
                result = FALSE
            end if
            
            '# remove hooks
            SetConsoleCtrlhandler(@_child_console_handler, FALSE)
            
            '# clean up all open handles
            CloseHandle(child)
        end if '# (pid > 0)
        
        return result
    end function
    
    
    '# Special hook used to avoid the process calling Terminate()
    '# respond to CTRL_*_EVENTS when terminating child process
    private function _child_console_handler(byval dwCtrlType as DWORD) as BOOL
        dim result as BOOL
        
        debug("_child_console_handler, dwCtrlType: " + str(dwCtrlType))
        if (dwCtrlType = CTRL_C_EVENT) then
            result = TRUE
        elseif (dwCtrlType = CTRL_BREAK_EVENT) then
            result = TRUE
        end if
        
        return result
    end function
end namespace '# fb.process
end namespace '# fb
