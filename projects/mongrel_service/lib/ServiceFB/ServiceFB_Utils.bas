'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#include once "ServiceFB.bi"
#include once "_internals.bi"
#include once "ServiceFB_Utils.bi"
#include once "_utils_internals.bi"

namespace fb
namespace svc
namespace utils   '# fb.svc.utils
    '# private (internals) for ServiceProcess.Console()
    dim shared _svc_stop_signal as any ptr
    dim shared _svc_in_console as ServiceProcess ptr
    dim shared _svc_in_console_stop_flag as BOOL
    
    '#####################
    '# ServiceController
    '# ctor()
    constructor ServiceController()
        with this
            .product = "My Product"
            .version = "v0.1"
            .copyright = "my copyright goes here."
        end with
    end constructor
    
    
    '# ctor(product)
    constructor ServiceController(byref new_product as string)
        this.product = new_product
    end constructor
    
    
    '# ctor(product, version)
    constructor ServiceController(byref new_product as string, byref new_version as string)
        constructor(new_product)
        this.version = new_version
    end constructor
    
    
    '# ctor(product, version, copyright)
    constructor ServiceController(byref new_product as string, byref new_version as string, byref new_copyright as string)
        constructor(new_product, new_version)
        this.copyright = new_copyright
    end constructor
    
    
    '# dtor()
    destructor ServiceController()
    end destructor
    
    
    '# Banner() will display in the console, information regarding your program
    '# using this formatting:
    '# 'Product', 'Version'
    '# 'Copyright'
    sub ServiceController.Banner()
        '# display Product and Version
        print this.product; ", "; this.version
        print this.copyright
        print ""
        '# leave a empty line between banner (header) and other info
    end sub
    
    
    '# RunMode() provide a simple way to get (*you*) from where this process was started
    '# and do the corresponding action.
    function ServiceController.RunMode() as ServiceRunMode
        dim result as ServiceRunMode
        dim currPID as DWORD
        dim parent_pid as uinteger
        dim parent_name as string
        dim start_mode as string
        
        _dprint("ServiceController.RunMode()")
        
        '# get this process PID
        currPID = GetCurrentProcessId()
        _dprint("CurrentPID: " + str(currPID))
        
        '# get the parent PID
        parent_pid = _parent_pid(currPID)
        _dprint("ParentPID: " + str(parent_pid))
        
        '# now the the name
        parent_name = _process_name(parent_pid)
        _dprint("Parent Name: " + parent_name)
        
        '# this process started as service?
        '# that means his parent is services.exe
        if (parent_name = "services.exe") then
            result = RunAsService
        else
            '# ok, it didn't start as service, analyze command line then
            start_mode = lcase(trim(command(1)))
            if (start_mode = "manage") then 
                '# start ServiceController.Manage()
                result = RunAsManager
            elseif (start_mode = "console") then
                '# start ServiceController.Console()
                result = RunAsConsole
            else
                '# ok, the first paramenter in the commandline didn't work,
                '# report back so we could send the banner!
                result = RunAsUnknown
            end if
        end if
        
        _dprint("ServiceController.RunMode() done")
        return result
    end function
    
    
    '# Manage will offer the user (end-user) option in the commandline to
    '# install, remove, start, stop and query the status of the installed service
    '# use Manage() when you code a multi-services (ServiceHost) based programs
    '# for single services, use Manage(service)
    sub ServiceController.Manage()
    end sub
    
    
    '# this is used when you want management capabilities for your service
    '# use this for single services, or call Manage() for multi services 
    sub ServiceController.Manage(byref service as ServiceProcess)
    end sub
    
    
    '# this offer the user a way to test/debug your service or run it like a normal
    '# program, from the command line
    '# will let you SHUTDOWN the service using CTRL+C
    '# use this for multi-services (ServiceHost) based programs
    sub ServiceController.Console()
        dim working_thread as any ptr
        dim run_mode as string
        dim service_name as string
        dim service as ServiceProcess ptr
        dim commandline as string
        dim success as integer
        
        _dprint("ServiceController.Console()")
        
        '# show the controller banner
        this.Banner()
        
        '# determine how many service exist in references
        if (_svc_references_count > 0) then
            _build_commandline(run_mode, service_name, commandline)
            service = _find_in_references(service_name)
            
            if (service = 0) then
                '# no valid service reference, list available services
                _list_references()
            else
                '# build the command line, excluding 'console' and service_name
                service->commandline = commandline
                
                '# got a service reference
                '# also, set the global handler that will be used by _control_handler
                _svc_in_console = service
                
                '# create the signal used to stop the service thread.
                _svc_stop_signal = condcreate()
                
                '# register the Console Handler
                SetConsoleCtrlHandler(@_console_handler, TRUE)
                
                print "Starting service '"; service_name; "' in console mode, please wait..."
                
                '# onInit should be started inline,
                '# and its result validated!
                if not (service->onInit = 0) then
                    success = service->onInit(*service)
                end if
                
                '# only continue if success
                if not (success = 0) then
                    '# now set service.state to running
                    service->state = Running
                    
                    '# now, fire the main loop (onStart)
                    if not (service->onStart = 0) then
                        '# create the thread
                        working_thread = threadcreate(service->onStart, cint(service))
                    end if
                    
                    print "Service is in running state."
                    print "Press Ctrl-C to stop it."
                
                    '# now that onStart is running, must monitor the stop_signal
                    '# in case it arrives, the service state must change to exit the
                    '# working thread.
                    condwait(_svc_stop_signal)
                    
                    print "Stop signal received, stopping..."
                    
                    '# received the signal, so set state = Stopped
                    service->state = Stopped
                    
                    print "Waiting for onStart() to exit..."
                    
                    '# now wait for the thread to terminate
                    if not (working_thread = 0) then
                        threadwait(working_thread)
                    end if
                    
                else
                    print "Error starting the service, onInit() failed."
                end if
                
                print "Service stopped, doing cleanup."
                
                '# remove the console handler
                SetConsoleCtrlHandler(@_console_handler, FALSE)
                
                '# now that service was stopped, destroy the references.
                conddestroy(_svc_stop_signal)
                
                print "Done."
            end if
        else
            print "ERROR: No services could be served by this program. Exiting."
        end if
        
        _dprint("ServiceController.Console() done")
    end sub
    
    
    '# this offer the user a way to test/debug your service or run it like a normal
    '# program, from the command line
    '# will let you SHUTDOWN the service using CTRL+C
    '# use this for single-services
    sub ServiceController.Console(byref service as ServiceProcess)
        
        _dprint("ServiceController.RunMode(service)")
        
        '# register the service in the references table
        _add_to_references(service)
        
        _dprint("delegate to Console()")
        '# now delegate control to Console()
        this.Console()
        
        _dprint("ServiceController.Console(service) done")
    end sub
    
    
    '# console_handler is used to get feedback form keyboard and allow
    '# shutdown of service using Ctrl+C / Ctrl+Break from keyboard
    function _console_handler(byval dwCtrlType as DWORD) as BOOL
        dim result as BOOL
        dim service as ServiceProcess ptr
        
        _dprint("_console_handler()")
        
        '# get the reference from svc_in_console
        service = _svc_in_console
        
        '# we default processing of the message to false
        result = FALSE
        
        '# avoid recursion problems
        if (_svc_in_console_stop_flag = FALSE) then
            _dprint("no previous signaled, process event")
            '# all the CtrlType events listed will raise the onStop
            '# of the service
            '# here also will be raised the _svc_stop_signal
            select case dwCtrlType
                case CTRL_C_EVENT, CTRL_CLOSE_EVENT, CTRL_BREAK_EVENT, CTRL_LOGOFF_EVENT, CTRL_SHUTDOWN_EVENT:
                    _dprint("got supported CTRL_*_EVENT")
                    '# avoid recursion problems
                    _svc_in_console_stop_flag = TRUE
                    _dprint("set signaled to TRUE")
                    
                    '# the service defined onStop?
                    if not (service->onStop = 0) then
                        _dprint("pass control to onStop()")
                        service->onStop(*service)
                    end if
                    
                    '# now fire the signal
                    _dprint("fire stop signal")
                    condsignal(_svc_stop_signal)
                    result = TRUE
                    _svc_in_console_stop_flag = FALSE
                    
                case else:
                    _dprint("unsupported CTRL EVENT")
                    result = FALSE
            end select
        else
            _dprint("already running onStop(), do not pass the message to other message handlers!")
            result = TRUE
        end if
        
        _dprint("_console_handler() done")
        return result
    end function
    
    
    '# helper private subs used to list the services and their descriptions 
    '# in _svc_references
    private sub _list_references()
        dim item as ServiceProcess ptr
        dim idx as integer
        
        print "Available services in this program:"
        
        for idx = 0 to (_svc_references_count - 1)
            item = _svc_references[idx]
            
            print space(2);
            print trim(item->name), , trim(item->description)
        next idx
        
    end sub
    
    
    '# TODO: SimpleLogger
    '# TODO: EventLogger
    
    
    '#####################
    '# private (internals)
    '# _parent_pid is used to retrieve, based on the PID you passed by, the one of the parent
    '# that launched that process.
    '# on fail, it will return 0
    '# Thanks to MichaelW (FreeBASIC forums) for his help about this.
    private function _parent_pid(PID as uinteger) as uinteger
        dim as uinteger result
        dim as HANDLE hProcessSnap
        dim as PROCESSENTRY32 pe32
        
        '# initialize result, 0 = fail, other number, ParentPID
        result = 0
        
        hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
        if not (hProcessSnap = INVALID_HANDLE_VALUE) then
            pe32.dwSize = sizeof(PROCESSENTRY32)
            if (Process32First(hProcessSnap, @pe32) = TRUE) then
                do
                    if (pe32.th32ProcessID = PID) then
                        result = pe32.th32ParentProcessID
                        exit do
                    end if
                loop while not (Process32Next(hProcessSnap, @pe32) = 0)
            end if
        end if
        
        CloseHandle(hProcessSnap)
        return result
    end function
    
    
    '# _process_name is used to retrieve the name (ImageName, BaseModule, whatever) of the PID you
    '# pass to it. if no module name was found, it should return <unknown>
    private function _process_name(PID as uinteger) as string
        dim result as string
        dim hProcess as HANDLE
        dim hMod as HMODULE
        dim cbNeeded as DWORD
        
        '# assign "<unknown>" to process name, allocate MAX_PATH (260 bytes)
        result = "<unknown>" 
        result += space(MAX_PATH - len(result))
    
        '# get a handle to the Process
        hProcess = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, FALSE, PID)
        
        '# if valid, get the process name
        if not (hProcess = NULL) then
            '# success getting Process modules
            if not (EnumProcessModules(hProcess, @hMod, sizeof(hMod), @cbNeeded) = 0) then
                result = space(cbNeeded)
                GetModuleBaseName(hProcess, hMod, strptr(result), len(result))
            end if
        end if
        
        CloseHandle(hProcess)
        
        '# return a trimmed result
        result = trim(result)
        return result
    end function
end namespace     '# fb.svc.utils
end namespace     '# fb.svc
end namespace     '# fb
