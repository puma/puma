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
'# use ServiceFB.bi instead
'#
'##################################################################

namespace fb
namespace svc
    '# now due references locking, I needed a constructor and destructor for 
    '# the namespace to garantee everything is cleaned up on termination of the process
    declare sub _initialize() constructor
    declare sub _terminate() destructor
    
    '# global service procedures (private)
    declare sub _main(as DWORD, as LPSTR ptr)
    declare function _control_ex(as DWORD, as DWORD, as LPVOID, as LPVOID) as DWORD
    declare sub _run()
    
    '# global references helper
    declare function _add_to_references(byref as ServiceProcess) as integer
    declare function _find_in_references(byref as string) as ServiceProcess ptr
    
    '# command line builder (helper)
    '# this is used to gather information about:
    '# mode (if present)
    '# valid service name (after lookup in the table)
    '# command line to be passed to service
    declare sub _build_commandline(byref as string, byref as string, byref as string)
    
    '# I started this as simple, unique service served from one process
    '# but the idea of share the same process space (and reduce resources use) was good.
    '# to do that, I needed a references table (similar to service_table, but we will
    '# hold the ServiceProcess registered by ServiceHost (the multi services host).
    '# also, I needed a locking mechanism to avoid problems of two calls changing the table
    '# at the same time.
    extern _svc_references as ServiceProcess ptr ptr
    extern _svc_references_count as integer
    extern _svc_references_lock as any ptr
end namespace   '# fb.svc
end namespace   '# fb

