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
'# - FreeBASIC 0.18
'# 
'##################################################################

#include once "mongrel_service.bi"
#define DEBUG_LOG_FILE EXEPATH + "\mongrel_service.log"
#include once "_debug.bi"

namespace mongrel_service
    constructor SingleMongrel()
        dim redirect_file as string
        
        with this.__service
            .name = "single"
            .description = "Mongrel Single Process service"
            
            '# disabling shared process
            .shared_process = FALSE
            
            '# TODO: fix inheritance here
            .onInit = @single_onInit
            .onStart = @single_onStart
            .onStop = @single_onStop
        end with
        
        with this.__console
            redirect_file = EXEPATH + "\mongrel.log"
            debug("redirecting to: " + redirect_file)
            .redirect(ProcessStdBoth, redirect_file)
        end with
        
        '# TODO: fix inheritance here
        single_mongrel_ref = @this
    end constructor
    
    destructor SingleMongrel()
        '# TODO: fin inheritance here
    end destructor
    
    function single_onInit(byref self as ServiceProcess) as integer
        dim result as integer
        dim mongrel_cmd as string
        
        debug("single_onInit()")
        
        '# ruby.exe must be in the path, which we guess is already there.
        '# because mongrel_service executable (.exe) is located in the same
        '# folder than mongrel_rails ruby script, we complete the path with
        '# EXEPATH + "\mongrel_rails" to make it work.
        '# FIXED ruby installation outside PATH and inside folders with spaces
        mongrel_cmd = !"\"" + EXEPATH + !"\\ruby.exe" + !"\" " + !"\"" + EXEPATH + !"\\mongrel_rails" + !"\"" + " start"
        
        '# due lack of inheritance, we use single_mongrel_ref as pointer to 
        '# SingleMongrel instance. now we should call StillAlive
        self.StillAlive()
        if (len(self.commandline) > 0) then
            '# assign the program
            single_mongrel_ref->__console.filename = mongrel_cmd
            single_mongrel_ref->__console.arguments = self.commandline
            
            '# fix commandline, it currently contains params to be passed to
            '# mongrel_rails, and not ruby.exe nor the script to be run.
            self.commandline = mongrel_cmd + " " + self.commandline
            
            '# now launch the child process
            debug("starting child process with cmdline: " + self.commandline)
            single_mongrel_ref->__child_pid = 0
            if (single_mongrel_ref->__console.start() = true) then
                single_mongrel_ref->__child_pid = single_mongrel_ref->__console.pid
            end if
            self.StillAlive()
            
            '# check if pid is valid
            if (single_mongrel_ref->__child_pid > 0) then
                '# it worked
                debug("child process pid: " + str(single_mongrel_ref->__child_pid))
                result = not FALSE
            end if
        else
            '# if no param, no service!
            debug("no parameters was passed to this service!")
            result = FALSE
        end if
        
        debug("single_onInit() done")
        return result
    end function
    
    sub single_onStart(byref self as ServiceProcess)
        debug("single_onStart()")
        
        do while (self.state = Running) or (self.state = Paused)
            '# instead of sitting idle here, we must monitor the pid
            '# and re-spawn a new process if needed
            if not (single_mongrel_ref->__console.running = true) then
                '# check if we aren't terminating
                if (self.state = Running) or (self.state = Paused) then
                    debug("child process terminated!, re-spawning a new one")
                    
                    single_mongrel_ref->__child_pid = 0
                    if (single_mongrel_ref->__console.start() = true) then
                        single_mongrel_ref->__child_pid = single_mongrel_ref->__console.pid
                    end if
                    
                    if (single_mongrel_ref->__child_pid > 0) then
                        debug("new child process pid: " + str(single_mongrel_ref->__child_pid))
                    end if
                end if
            end if
            
            '# wait for 5 seconds
            sleep 5000
        loop
        
        debug("single_onStart() done")
    end sub
    
    sub single_onStop(byref self as ServiceProcess)
        debug("single_onStop()")
        
        '# now terminates the child process
        if not (single_mongrel_ref->__child_pid = 0) then
            debug("trying to kill pid: " + str(single_mongrel_ref->__child_pid))
            if not (single_mongrel_ref->__console.terminate() = true) then
                debug("Terminate() reported a problem when terminating process " + str(single_mongrel_ref->__child_pid))
            else
                debug("child process terminated with success.")
                single_mongrel_ref->__child_pid = 0
            end if
        end if
        
        debug("single_onStop() done")
    end sub
    
    sub application()
        dim simple as SingleMongrel
        dim host as ServiceHost
        dim ctrl as ServiceController = ServiceController("Mongrel Win32 Service", "version " + VERSION, _
                                                            "(c) 2006 The Mongrel development team.")
        
        '# add SingleMongrel (service)
        host.Add(simple.__service)
        select case ctrl.RunMode()
            '# call from Service Control Manager (SCM)
            case RunAsService:
                debug("ServiceHost RunAsService")
                host.Run()
                
            '# call from console, useful for debug purposes.
            case RunAsConsole:
                debug("ServiceController Console")
                ctrl.Console()
                
            case else:
                ctrl.Banner()
                print "mongrel_service is not designed to run form commandline,"
                print "please use mongrel_rails service:: commands to create a win32 service."
        end select
    end sub
end namespace

'# MAIN: start native mongrel_service here
mongrel_service.application()
