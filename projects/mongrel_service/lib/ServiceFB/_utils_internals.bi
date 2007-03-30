'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# Permission is hereby granted, free of charge, to any person obtaining
'# a copy of this software and associated documentation files (the
'# "Software"), to deal in the Software without restriction, including
'# without limitation the rights to use, copy, modify, merge, publish,
'# distribute, sublicense, and/or sell copies of the Software, and to
'# permit persons to whom the Software is furnished to do so, subject to
'# the following conditions:
'#
'# The above copyright notice and this permission notice shall be
'# included in all copies or substantial portions of the Software.
'#
'# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
'# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
'# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
'# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
'# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
'# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
'# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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
    declare function _parent_pid(as uinteger) as uinteger
    declare function _process_name(as uinteger) as string
    
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
