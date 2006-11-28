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

#ifndef __Debug_bi__
#define __Debug_bi__

#ifdef DEBUG_LOG
    #include once "vbcompat.bi"
    #ifndef DEBUG_LOG_FILE
        #define DEBUG_LOG_FILE EXEPATH + "\debug.log"
    #endif

    '# this procedure is only used for debugging purposed, will be removed from
    '# final compilation
    private sub debug_to_file(byref message as string, byref file as string, byval linenumber as uinteger, byref func as string)
        dim handle as integer
        static first_time as integer
        
        handle = freefile
        open DEBUG_LOG_FILE for append as #handle
        
        if (first_time = 0) then
            print #handle, "# Logfile created on "; format(now(), "dd/mm/yyyy HH:mm:ss")
            print #handle, ""
            first_time = 1
        end if
        
        '# src/module.bas:123, namespace.function:
        '#   message
        '#
        print #handle, file; ":"; str(linenumber); ", "; lcase(func); ":"
        print #handle, space(2); message
        print #handle, ""
        
        close #handle
    end sub
    #define debug(message) debug_to_file(message, __FILE__, __LINE__, __FUNCTION__)
#else
    #define debug(message)
#endif '# DEBUG_LOG

#endif '# __Debug_bi__
