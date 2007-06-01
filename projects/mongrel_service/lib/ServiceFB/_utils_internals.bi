'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

'##################################################################
'#
'# DO NOT INCLUDE THIS FILE DIRECTLY!
'# it is used internaly by ServiceFB
'# use ServiceFB_Utils.bi instead
'#
'##################################################################

namespace fb
namespace svc
namespace utils   '# fb.svc.utils
    '# console_handler is used to get feedback form keyboard and allow
    '# shutdown of service using Ctrl+C / Ctrl+Break from keyboard
    declare function _console_handler(byval as DWORD) as BOOL
    
    '# helper private subs used to list the services and their descriptions 
    '# in _svc_references
    declare sub _list_references()
    
    '# internals functions used to get Parent PID and Process Name
    '# using this we automatically determine if the service was started by SCM
    '# or by the user, from commandline or from explorer
    declare function _parent_pid(byval as uinteger) as uinteger
    declare function _process_name(byval as uinteger) as string
    declare function _process_name_dyn_psapi(byval as uinteger) as string
    declare function _show_error() as string
    
    '# InStrRev (authored by ikkejw @ freebasic forums)
    '# http://www.freebasic.net/forum/viewtopic.php?p=49315#49315
    declare function InStrRev(byval as uinteger = 0, byref as string, byref as string) as uinteger
    
    '# use a signal (condition) in the console mode to know
    '# when the service should be stopped.
    '# the Console() main loop will wait for it, and the console_handler
    '# will raise in case Ctrl+C / Ctrl+Break or other events are
    '# received.
    extern _svc_stop_signal as any ptr
    extern _svc_in_console as ServiceProcess ptr
    extern _svc_in_console_stop_flag as BOOL
end namespace     '# fb.svc.utils
end namespace     '# fb.svc
end namespace     '# fb
