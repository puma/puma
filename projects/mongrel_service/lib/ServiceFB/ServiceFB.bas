'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#include once "ServiceFB.bi"
#include once "_internals.bi"

namespace fb
namespace svc
    '# I started this as simple, unique service served from one process
    '# but the idea of share the same process space (and reduce resources use) was good.
    '# to do that, I needed a references table (similar to service_table, but we will
    '# hold the ServiceProcess registered by ServiceHost (the multi services host).
    '# also, I needed a locking mechanism to avoid problems of two calls changing the table
    '# at the same time.
    dim shared _svc_references as ServiceProcess ptr ptr
    dim shared _svc_references_count as integer
    dim shared _svc_references_lock as any ptr
    
    
    '#####################
    '# ServiceProcess
    '# ctor()
    constructor ServiceProcess()
        constructor("NewServiceProcess")
    end constructor
    
    
    '# ctor(name)
    constructor ServiceProcess(byref new_name as string)
        _dprint("ServiceProcess(new_name)")
        '# assign the service name
        this.name = new_name

        '# initialize the status structure
        with this._svcStatus
            .dwServiceType = SERVICE_WIN32_OWN_PROCESS
            .dwCurrentState = SERVICE_STOPPED
            .dwControlsAccepted = (SERVICE_ACCEPT_STOP or SERVICE_ACCEPT_SHUTDOWN)
            .dwWin32ExitCode = NO_ERROR
            .dwServiceSpecificExitCode = NO_ERROR
            .dwCheckPoint = 0
            .dwWaitHint = 0
        end with
        
        '# use a state placeholder
        this.state = this._svcStatus.dwCurrentState
        
        '# disable shared process by default
        this.shared_process = FALSE
        
        '# create the stop event
        this._svcStopEvent = CreateEvent( 0, FALSE, FALSE, 0 )
        _dprint("ServiceProcess(new_name) done")
    end constructor
    
    
    '# dtor()
    destructor ServiceProcess()
        _dprint("ServiceProcess() destructor")
        '# safe to destroy it. anyway, just checking
        with this
            .onInit = 0
            .onStart = 0
            .onStop = 0
            .onPause = 0
            .onContinue = 0
            ._threadHandle = 0
            CloseHandle(._svcStopEvent)
        end with
        _dprint("ServiceProcess() destructor done")
    end destructor
    
    
    '# for single process, here I create the references table and then 
    '# delegate control to _run() which will call the service control dispatcher
    sub ServiceProcess.Run()
        _dprint("ServiceProcess.Run()")
        
        '# add the unique reference
        _add_to_references(this)
        
        '# delegate control to _run()
        _run()
        
        _dprint("ServiceProcess.Run() done")
    end sub
    
    
    '# I use this method to simplify changing the service state 
    '# notification to the service manager.
    '# is needed to set dwControlsAccepted = 0 if state is SERVICE_*_PENDING
    '# also, StillAlive() call it to set the checkpoint and waithint
    '# to avoid SCM shut us down.
    '# is not for the the end-user (*you*) to access it, but implemented in this
    '# way to reduce needed to pass the right service reference each time
    sub ServiceProcess.UpdateState(byval state as DWORD, byval checkpoint as integer = 0, byval waithint as integer = 0)
        _dprint("ServiceProcess.UpdateState()")
        '# set the state
        select case state
            '# if the service is starting or stopping, I must disable the option to accept
            '# other controls form SCM.
            case SERVICE_START_PENDING, SERVICE_STOP_PENDING:
                this._svcStatus.dwControlsAccepted = 0
            
            '# in this case, running or paused, stop and shutdown must be available
            '# also, we must check here if our service is capable of pause/continue ç
            '# functionality and allow them (or not).
            case SERVICE_RUNNING, SERVICE_PAUSED:
                this._svcStatus.dwControlsAccepted = (SERVICE_ACCEPT_STOP or SERVICE_ACCEPT_SHUTDOWN)
                
                '# from start, the service accept stop and shutdown (see ctor(name)).
                '# configure the accepted controls.
                '# Pause and Continue only will be enabled if you setup onPause and onContinue
                if not (this.onPause = 0) and _
                    not (this.onContinue = 0) then
                    this._svcStatus.dwControlsAccepted or= SERVICE_ACCEPT_PAUSE_CONTINUE
                end if
                
        end select
        
        '# set the structure status
        '# also the property
        this._svcStatus.dwCurrentState = state
        this.state = state
        
        '# set checkpoint and waithint
        this._svcStatus.dwCheckPoint = checkpoint
        this._svcStatus.dwWaitHint = waithint
        
        '# call the API
        '# only we will call is _svcHandle is valid
        '# this will allow use of UpdateState (and StillAlive) from console
        if not (this._svcHandle = 0) then
            _dprint("SetServiceStatus() API")
            SetServiceStatus(this._svcHandle, @this._svcStatus)
        end if
        _dprint("ServiceProcess.UpdateState() done")
    end sub
    
    
    '# use StillAlive() method when performing lengthly tasks during onInit or onStop
    '# (if they take too much time).
    '# by default we set a wait hint gap of 10 seconds, but you could specify how many
    '# you could specify how many seconds more will require your *work*
    sub ServiceProcess.StillAlive(byval waithint as integer = 10)
        dim as integer checkpoint

        _dprint("ServiceProcess.StillAlive()")
        '# start or stop pending?
        if (this._svcStatus.dwCurrentState = SERVICE_START_PENDING) or _
            (this._svcStatus.dwCurrentState = SERVICE_STOP_PENDING) then
                with this
                    checkpoint = this._svcStatus.dwCheckPoint
                    checkpoint += 1
                    .UpdateState(._svcStatus.dwCurrentState, checkpoint, (waithint * 1000))
                end with
        end if
        _dprint("ServiceProcess.StillAlive() done")
    end sub
    
    
    '#####################
    '# ServiceHost
    '# ctor()
    '# currently isn't needed, why I defined it?
    constructor ServiceHost()
        _dprint("ServiceHost()")
        _dprint("ServiceHost() done")
    end constructor
    
    
    '# dtor()
    '# currently isn't needed, why I defined it?
    destructor ServiceHost()
        _dprint("ServiceHost() destructor")
        _dprint("ServiceHost() destructor done")
    end destructor
    
    
    '# using Add() will register an already initialized service into the references
    '# table, which will be used later to launch and control the different services
    '# we should be careful when handling references, so for that reference_lock is
    '# provided ;-)
    sub ServiceHost.Add(byref service as ServiceProcess)
        _dprint("ServiceHost.Add()")
        
        '# add the service reference to the references table
        '# get the new count as result, so
        '# increment the local counter
        this.count = _add_to_references(service)
        
        _dprint("ServiceHost.Add() done")
    end sub
    
    
    '# ServiceHost.Run() is just a placeholder, it delegates control to _run()
    '# pretty simple, but still must be present to simplify user interaction.
    sub ServiceHost.Run()
        _dprint("ServiceHost.Run()")
        
        '# the longest, hard coded function in the world!
        '# just kidding
        _run()
        
        _dprint("ServiceHost.Run() done")
    end sub
    
    
    '# the purpose of this sub is provide a generic service creation and running
    '# this is be called from exisitng ServiceProcess and ServiceHost.
    '# this construct the SERVICE_TABLE_ENTRY based on the the references table,
    '# which will be sent to StartServiceCtrlDispatcher()
    private sub _run()
        dim ServiceTable(_svc_references_count) as SERVICE_TABLE_ENTRY
        dim idx as integer
        
        _dprint("_run()")
        
        _dprint("creating service table for " + str(_svc_references_count) + " services")
        for idx = 0 to (_svc_references_count - 1)
            '# we take the service name from the references and set as ServiceMain the same
            '# _main() routine for all the services
            ServiceTable(idx) = type<SERVICE_TABLE_ENTRY>(strptr(_svc_references[idx]->name), @_main)
            _dprint(str(idx) + ": " + _svc_references[idx]->name)
        next idx
        '# last member of the table must be null
        ServiceTable(_svc_references_count) = type<SERVICE_TABLE_ENTRY>(0, 0)
        _dprint("service table created")
        
        '# start the dispatcher
        _dprint("start service dispatcher")
        StartServiceCtrlDispatcher( @ServiceTable(0) )
        
        _dprint("_run() done")
    end sub
    
    
    '# this sub is fired by StartServiceCtrlDispatcher in another thread.
    '# because it is a global _main for all the services in the table, looking up
    '# in the references for the right service is needed prior registering its
    '# control handler.
    private sub _main(byval argc as DWORD, byval argv as LPSTR ptr)
        dim success as integer
        dim service as ServiceProcess ptr
        dim run_mode as string
        dim service_name as string
        dim commandline as string
        dim param_line as string
        dim temp as string
        
        _dprint("_main()")
        
        '# debug dump of argc and argv
        dim idx as integer = 0
        for idx = 0 to (argc - 1)
            _dprint(str(idx) + ": " + *argv[idx])
        next idx
        
        '# retrieve all the information (mode, service name and command line
        _build_commandline(run_mode, service_name, commandline)
        service = _find_in_references(service_name)
        
        '# build parameter line (passed from SCM)
        if (argc > 1) then
            param_line = ""
            for idx = 1 to (argc - 1)
                temp = *argv[idx]
                if (instr(temp, chr(32)) > 0) then
                    param_line += """" + temp + """"
                else
                    param_line += temp
                end if
                param_line += " "
            next idx
        end if
        
        '# parameters passed using SCM have priority over ImagePath ones
        if not (len(param_line) = 0) then
            commandline = param_line
        end if
        
        '# a philosofical question: to run or not to run?
        if not (service = 0) then
            _dprint("got a valid service reference")
            _dprint("real service name: " + service->name)
            
            '# pass to the service the commandline
            _dprint("passing service commandline: " + commandline)
            service->commandline = commandline
            
            '# ok, its a service!, its alive!
            '# register his ControlHandlerEx
            _dprint("register control handler ex")
            service->_svcHandle = RegisterServiceCtrlHandlerEx(strptr(service_name), @_control_ex, cast(LPVOID, service))
            
            '# check if evething is done right
            if not (service->_svcHandle = 0) then
                '# now, we are a single service or a bunch, like the bradys?
                if (_svc_references_count > 1) then
                    '# determine if we share or not the process
                    if (service->shared_process = FALSE) then
                        service->_svcStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS
                    else
                        '# this mean we will be sharing... hope neighbors don't crash the house!
                        service->_svcStatus.dwServiceType = SERVICE_WIN32_SHARE_PROCESS
                    end if
                else
                    '# ok, we have a full house (ehem, process) for us only!
                    service->_svcStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS
                end if
                
                '# START_PENDING
                _dprint("service start pending")
                service->UpdateState(SERVICE_START_PENDING)
                
                '# now delegate to the long running initialization if it exist.
                if not (service->onInit = 0) then
                    _dprint("pass control to lengthly initialization")
                    success = service->onInit(*service)
                else
                    '# if no onInit was defined (maybe you don't need it?)
                    '# we should simulate it was successful to proceed
                    success = (-1)
                end if
                _dprint("onInit result: " + str(success))
                
                '# check if everything is ok
                '# if onInit showed problems, 0 was returned and service must not continue
                if not (success = 0) then
                    '# SERVICE_RUNNING
                    '# we must launch the onStart as thread, but first setting state as running
                    service->UpdateState(SERVICE_RUNNING)
                    if not (service->onStart = 0) then
                        _dprint("dispatch onStart() as new thread")
                        service->_threadHandle = threadcreate(service->onStart, service)
                        '# my guess? was a hit!
                    end if
                    
                    '# now that we are out of onStart thread, check if actually hit the stop sign
                    _dprint("waiting for stop signal")
                    do
                        '# do nothing ...
                        '# but not too often!
                    loop while (WaitForSingleObject(service->_svcStopEvent, 100) = WAIT_TIMEOUT)
                    
                    '# now, wait for the thread (anyway, I hope it will be checking this.state, right?)
                    '# we should do this, or actualy jump and wait for StopEvent?
                    _dprint("waiting for onStart() thread to finish")
                    threadwait(service->_threadHandle)
                end if
                
                '# if we reach here, that means the service is not running, and the onStop was performed
                '# so no more chat, stop it one and for all!
                '# set SERVICE_STOPPED (just checking)
                _dprint("service stopped")
                service->UpdateState(SERVICE_STOPPED)
            end if
            
            '# ok, we are done!
        end if
        
        _dprint("_main() done")
    end sub
    
    
    '# this sub is used by _main when registering the ControlHandler for this service 
    '# (as callback from service manager).
    '# we process each control codes and perform the actions using the pseudo-events (callbacks)
    '# also we use lpContext to get the right reference when _main registered the control handler.
    private function _control_ex(byval dwControl as DWORD, byval dwEventType as DWORD, byval lpEventData as LPVOID, byval lpContext as LPVOID) as DWORD
        dim result as DWORD
        dim service as ServiceProcess ptr
        
        _dprint("_control_ex()")
        
        '# we get a reference form the context
        service = cast(ServiceProcess ptr, lpContext)
        
        '# show if the service reference is valid?
        _dprint("service name: " + service->name)
        
        select case dwControl
            case SERVICE_CONTROL_INTERROGATE:
                '# we are running, so what we should do here?
                _dprint("interrogation signal received")
                '# in case we get a interrogation, we always should answer this way.
                result = NO_ERROR
                
            case SERVICE_CONTROL_SHUTDOWN, SERVICE_CONTROL_STOP:
                _dprint("stop signal received")
                '# ok, service manager requested us to stop.
                '# we must call onStop if was defined.
                service->UpdateState(SERVICE_STOP_PENDING)
                if not (service->onStop = 0) then
                    _dprint("pass control to onStop()")
                    service->onStop(*service)
                end if
                '# now signal the stop event so _main could take care of the rest.
                _dprint("signal stop event")
                SetEvent(service->_svcStopEvent)
                
            case SERVICE_CONTROL_PAUSE:
                _dprint("pause signal received")
                '# we must check if we could answer to the request.
                if not (service->onPause = 0) and _
                    not (service->onContinue = 0) then
                    
                    '# just to be sure
                    if not (service->onPause = 0) then
                        service->UpdateState(SERVICE_PAUSE_PENDING)
                        
                        _dprint("pass control to onPause()")
                        service->onPause(*service)
                        
                        service->UpdateState(SERVICE_PAUSED)
                        _dprint("service paused")
                    end if
                    result = NO_ERROR
                    
                else
                    '# ok, our service didn't support pause or continue
                    '# tell the service manager about that!
                    result = ERROR_CALL_NOT_IMPLEMENTED
                end if
                
            case SERVICE_CONTROL_CONTINUE:
                _dprint("continue signal received")
                '# we should resume from a paused state
                '# we must check if we could answer to the request.
                if not (service->onPause = 0) and _
                    not (service->onContinue = 0) then
                    
                    '# just to be sure
                    if not (service->onPause = 0) then
                        service->UpdateState(SERVICE_CONTINUE_PENDING)
                        
                        _dprint("pass control to onContinue()")
                        service->onContinue(*service)
                        
                        service->UpdateState(SERVICE_RUNNING)
                        _dprint("service running")
                    end if
                    result = NO_ERROR
                    
                else
                    '# ok, our service didn't support pause or continue
                    '# tell the service manager about that!
                    result = ERROR_CALL_NOT_IMPLEMENTED
                end if
                
            case else:
                result = NO_ERROR
        end select
        
        _dprint("_control_ex() done")
        return result
    end function
    
    
    '# add_to_references is a helper used to reduce code duplication (DRY).
    '# here is used a lock around _svc_references to avoid two threads try change the
    '# reference count (just in case).
    function _add_to_references(byref service as ServiceProcess) as integer
        _dprint("_add_to_references()")
        
        '# get a lock before even think touch references!
        mutexlock(_svc_references_lock)
        
        '# now, reallocate space
        _svc_references_count += 1
        _svc_references = reallocate(_svc_references, sizeof(ServiceProcess ptr) * _svc_references_count)
        
        '# put the reference of this service into the table
        _svc_references[(_svc_references_count - 1)] = @service
        
        '# ok, done, unlock our weapons! ;-)
        mutexunlock(_svc_references_lock)
        
        _dprint("_add_to_references() done")
        '# return the new references count
        return _svc_references_count
    end function
    
    
    '# find_in_references is used by _main to lookup for the specified service in 
    '# references table. 
    function _find_in_references(byref service_name as string) as ServiceProcess ptr
        dim result as ServiceProcess ptr
        dim item as ServiceProcess ptr
        dim idx as integer
        
        _dprint("_find_in_references()")
        
        '# we start with a pesimistic idea ;-)
        result = 0
        
        for idx = 0 to (_svc_references_count - 1)
            '# hold a reference to the item
            item = _svc_references[idx]
            
            '# compare if we have a match
            if (service_name = item->name) then
                result = item
                exit for
            end if
        next idx
        
        _dprint("_find_in_references() done")
        '# return the found (or not) reference
        return result
    end function
    
    
    '# namespace constructor
    '# first we must create the mutex to be used with references
    private sub _initialize() constructor
        _dprint("_initialize() constructor")
        '# we do this in case was already defined... don't know the situation,
        '# just to be sure
        if (_svc_references_lock = 0) then
            _svc_references_lock = mutexcreate()
            
            '# also initialize our count :-)
            _svc_references_count = 0
        end if
        
        _dprint("_initialize() constructor done")
    end sub
    
    
    '# namespace destructor
    private sub _terminate() destructor
        _dprint("_terminate() destructor")
        '# to avoid removing everything, we must lock to the references
        mutexlock(_svc_references_lock)
        
        '# destroy our refernces allocated memory!
        deallocate(_svc_references)
        
        '# unlock the mutex and destroy it too.
        mutexunlock(_svc_references_lock)
        mutexdestroy(_svc_references_lock)
        
        _dprint("_terminate() destructor done")
    end sub
    
    
    '# command line builder (helper)
    '# this is used to gather information about:
    '# mode (if present)
    '# valid service name (after lookup in the table)
    '# command line to be passed to service
    sub _build_commandline(byref mode as string, byref service_name as string, byref commandline as string)
        dim result_mode as string
        dim result_name as string
        dim result_cmdline as string
        dim service as ServiceProcess ptr
        dim idx as integer
        dim temp as string
        
        idx = 1
        '# first, determine if mode is pressent in commandline, must me command(1)
        temp = lcase(command(idx))
        
        if (temp = "console") or _
            (temp = "manage") then
            result_mode = temp
            idx += 1
        end if
        
        '# now, check if service name is present
        temp = command(idx)
        
        '# its present?
        if (len(temp) > 0) then
            '# lookup in references table
            service = _find_in_references(temp)
            if not (service = 0) then
                '# was found, so must be valid
                result_name = temp
                '# adjust start index for cmdline
                idx += 1
            end if
        end if

        '# is service valid?
        '# its really needed?
        if (service = 0) then
            if (_svc_references_count = 1) then
                '# no, get the first one
                service = _svc_references[0]
                result_name = service->name
                '# adjust start index for cmdline
            else
                '# this is needed!
                result_name = ""
            end if
        end if
        
        result_cmdline = ""
        
        temp = command(idx)
        do while (len(temp) > 0)
            if (instr(temp, chr(32)) > 0) then
                '# properly quote parameters with spaces
                result_cmdline += """" + temp + """"
            else
                result_cmdline += temp
            end if
            result_cmdline += " "
            idx += 1
            
            temp = command(idx)
        loop
        
        '# now, return the results
        mode = result_mode
        service_name = result_name
        commandline = result_cmdline
    end sub
    
    
    '# ### DEBUG ###
    '# just for debuging purposes 
    '# (will be removed in the future when Loggers get implemented)
#ifdef SERVICEFB_DEBUG_LOG
    sub _dprint(byref message as string)
        dim handle as integer
        
        handle = freefile
        open EXEPATH + "\servicefb.log" for append as #handle
        
        print #handle, message
        
        close #handle
    end sub
#endif
end namespace   '# fb.svc
end namespace   '# fb
