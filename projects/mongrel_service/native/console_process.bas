'#--
'# Copyright (c) 2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#include once "console_process.bi"

constructor ConsoleProcess(byref new_filename as string = "", byref new_arguments as string = "")
    '# assign filename and arguments
    
    '# if filename contains spaces, automatically quote it!
    if (instr(new_filename, " ") > 0) then
        _filename = !"\"" + new_filename + !"\""
    else
        _filename = new_filename
    endif
    
    _arguments = new_arguments
end constructor

destructor ConsoleProcess()
    '# in case process still running
    if (running = true) then
        terminate(true)
        
        '# close opened handles
        '# ...
        CloseHandle(_process_info.hProcess)
        CloseHandle(_process_info.hThread)
    end if
end destructor

property ConsoleProcess.filename() as string
    return _filename
end property

property ConsoleProcess.filename(byref rhs as string)
    if not (running = true) then
        _filename = rhs
    end if
end property

property ConsoleProcess.arguments() as string
    return _arguments
end property

property ConsoleProcess.arguments(byref rhs as string)
    if not (running = true) then
        _arguments = rhs
    end if
end property

property ConsoleProcess.redirected_stdout() as string
    return _stdout_filename
end property

property ConsoleProcess.redirected_stderr() as string
    return _stderr_filename
end property

'# running is a helper which evaluates _pid and exit_code
property ConsoleProcess.running() as boolean
    dim result as boolean

    '# presume not running
    result = false
    
    if not (_pid = 0) then
        '# that means the process is/was running.
        '# now evaluate if exit_code = STILL_ACTIVE
        result = (exit_code = STILL_ACTIVE)
    end if
    
    return result
end property

property ConsoleProcess.pid() as uinteger
    return _pid
end property

property ConsoleProcess.exit_code() as uinteger
    dim result as uinteger
    
    result = 0
    
    '# is _pid valid?
    if not (_pid = 0) then
        if not (_process_info.hProcess = NULL) then
            '# the process reference is valid, get the exit_code
            if not (GetExitCodeProcess(_process_info.hProcess, @result) = 0) then
                '# OK
                '# no error in the query, get result
            end if '# not (GetExitCodeProcess() = 0)
        end if '# not (proc = NULL)
    end if '# not (_pid = 0)
    
    return result
end property

function ConsoleProcess.redirect(byval target as ProcessStdEnum, byref new_std_filename as string) as boolean
    dim result as boolean
    
    if not (running = true) then
        select case target
            case ProcessStdOut:
                _stdout_filename = new_std_filename
                result = true
                
            case ProcessStdErr:
                _stderr_filename = new_std_filename
                result = true
                
            case ProcessStdBoth:
                _stdout_filename = new_std_filename
                _stderr_filename = new_std_filename
                result = true
        
        end select
    end if
    
    return result
end function

function ConsoleProcess.start() as boolean
    dim result as boolean
    dim success as boolean
    
    '# API
    '# New Process resources
    dim context as STARTUPINFO
    dim proc_sa as SECURITY_ATTRIBUTES = type(sizeof(SECURITY_ATTRIBUTES), NULL, TRUE)
    
    '# StdIn, StdOut, StdErr Read and Write Pipes.
    dim as HANDLE StdInRd, StdOutRd, StdErrRd
    dim as HANDLE StdInWr, StdOutWr, StdErrWr
    dim merged as boolean
    
    '# cmdline
    dim cmdline as string
    
    '# assume start will fail
    result = false
    
    if (running = false) then
        '# we should create the std* for the new proc!
        '# (like good parents, prepare everything!)
        
        '# to ensure everything will work, we must allocate a console
        '# using AllocConsole, even if it fails.
        '# This solve the problems when running as service.
        '# we discard result of AllocConsole since we ALWAYS will allocate it.
        AllocConsole()
        
        '# assume all the following steps succeed
        success = true
        
        '# StdIn is the only std that will be created using pipes always
        '# StdIn
        if (CreatePipe(@StdInRd, @StdInWr, @proc_sa, 0) = 0) then 
            success = false
        end if
        
        '# Ensure the handles to the pipe are not inherited.
        if (SetHandleInformation(StdInWr, HANDLE_FLAG_INHERIT, 0) = 0) then
            success = false
        end if
        
        '# StdOut and StdErr should be redirected?
        if (not _stdout_filename = "") or _
            (not _stderr_filename = "") then
            
            '# out and err are the same? (merged)
            if (_stdout_filename = _stderr_filename) then
                merged = true
            end if
        end if
        
        '# StdOut if stdout_filename
        if not (_stdout_filename = "") then
            StdOutWr = CreateFile(strptr(_stdout_filename), _
                                    GENERIC_WRITE, _
                                    FILE_SHARE_READ or FILE_SHARE_WRITE, _
                                    @proc_sa, _
                                    OPEN_ALWAYS, _
                                    FILE_ATTRIBUTE_NORMAL, _
                                    NULL)
            
            if (StdOutWr = INVALID_HANDLE_VALUE) then
                '# failed to open file
                success = false
            else
                SetFilePointer(StdOutWr, 0, NULL, FILE_END)
            end if
        else
            '# use pipes instead
            '# StdOut
            if (CreatePipe(@StdOutRd, @StdOutWr, @proc_sa, 0) = 0) then 
                success = false
            end if
            
            if (SetHandleInformation(StdOutRd, HANDLE_FLAG_INHERIT, 0) = 0) then
                success = false
            end if
        end if 'not (_stdout_filename = "")
        
        '# only create stderr if no merged.
        if (merged = true) then
            StdErrWr = StdOutWr
        else
            '# do the same for StdErr...
            if not (_stderr_filename = "") then
                StdErrWr = CreateFile(strptr(_stderr_filename), _
                                        GENERIC_WRITE, _
                                        FILE_SHARE_READ or FILE_SHARE_WRITE, _
                                        @proc_sa, _
                                        OPEN_ALWAYS, _
                                        FILE_ATTRIBUTE_NORMAL, _
                                        NULL)
                
                if (StdErrWr = INVALID_HANDLE_VALUE) then
                    '# failed to open file
                    success = false
                else
                    SetFilePointer(StdErrWr, 0, NULL, FILE_END)
                end if
            else
                '# use pipes instead
                '# StdOut
                if (CreatePipe(@StdErrRd, @StdErrWr, @proc_sa, 0) = 0) then 
                    success = false
                end if
                
                if (SetHandleInformation(StdErrRd, HANDLE_FLAG_INHERIT, 0) = 0) then
                    success = false
                end if
                
            end if 'not (_stderr_filename = "")
        end if '(merged = true)
        
        '# now we must proceed to create the process
        '# without the pipes, we shouldn't continue!
        if (success = true) then
            '# Set the Std* handles ;-)
            with context
                .cb = sizeof( context )
                .hStdError = StdErrWr
                .hStdOutput = StdOutWr
                .hStdInput = StdInRd
                .dwFlags = STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW
                '# FIXME: .wShowWindow = iif((_show_console = true), SW_SHOW, SW_HIDE)
                .wShowWindow = SW_HIDE
            end with
            
            '# build the command line
            cmdline = _filename + " " + _arguments
            
            '# now creates the process
            if (CreateProcess(NULL, _
                                strptr(cmdline), _
                                NULL, _
                                NULL, _
                                1, _            '# win32 TRUE (1)
                                0, _
                                NULL, _
                                NULL, _
                                @context, _
                                @_process_info) = 0) then
                result = false
            else
                '# set the _pid
                _pid = _process_info.dwProcessId
                
                '# OK? yeah, I think so.
                result = true
                
                '# close the Std* handles
                CloseHandle(StdInRd)
                CloseHandle(StdInWr)
                CloseHandle(StdOutRd)
                CloseHandle(StdOutWr)
                CloseHandle(StdErrRd)
                CloseHandle(StdErrWr)
                
                '# close children main Thread handle
                'CloseHandle(proc.hThread)
                'CloseHandle(proc.hProcess)
                
            end if '# (CreateProcess() = 0)
        else
            result = false
        end if '# (success = TRUE)
    end if
    
    return result
end function

function ConsoleProcess.terminate(byval force as boolean = false) as boolean
    dim result as boolean
    dim success as boolean
    
    dim proc as HANDLE
    dim code as uinteger
    dim wait_code as uinteger
    
    '# is pid valid?
    if (running = true) then
        '# hook our custom console handler
        if not (SetConsoleCtrlHandler(@_console_handler, 1) = 0) then
            success = true
        end if
        
        if (success = true) then
            '# get a handle to Process
            proc = _process_info.hProcess
            if not (proc = NULL) then
                '# process is valid, perform actions
                success = false
                
                if not (force = true) then
                    '# send CTRL_C_EVENT and wait for result
                    if not (GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) = 0) then
                        '# it worked, wait 5 seconds terminates.
                        wait_code = WaitForSingleObject(proc, 5000)
                        if not (wait_code = WAIT_TIMEOUT) then
                            success = true
                        end if
                    else
                        success = false
                    end if
                    
                    '# Ctrl-C didn't work, try Ctrl-Break
                    if (success = false) then
                        '# send CTRL_BREAK_EVENT and wait for result
                        if not (GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0) = 0) then
                            '# it worked, wait 5 seconds terminates.
                            wait_code = WaitForSingleObject(proc, 5000) 
                            if not (wait_code = WAIT_TIMEOUT) then
                                success = true
                            end if
                        else
                            success = false
                        end if
                    end if
                    
                '# only do termination if force was set.
                elseif (force = true) and (success = false) then
                    '# still no luck? we should do a hard kill then
                    if (TerminateProcess(proc, 0) = 0) then
                        success = false
                    else
                        success = true
                    end if
                end if
                
                '# now get process exit code
                if (success = true) then
                    result = true
                else
                    result = false
                end if
            else
                '# invalid process handler
                result = false
            end if
            
        end if '# (success = true)
        
        '# remove hooks
        if not (SetConsoleCtrlHandler(@_console_handler, 0) = 0) then
            success = true
        end if
    end if '# not (pid = 0)
    
    return result
end function

function ConsoleProcess._console_handler(byval dwCtrlType as DWORD) as BOOL
    dim result as BOOL
    
    if (dwCtrlType = CTRL_C_EVENT) then
        result = 1
    elseif (dwCtrlType = CTRL_BREAK_EVENT) then
        result = 1
    end if
    
    return result
end function
