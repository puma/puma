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
    declare sub _main(byval as DWORD, byval as LPSTR ptr)
    declare function _control_ex(byval as DWORD, byval as DWORD, byval as LPVOID, byval as LPVOID) as DWORD
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

