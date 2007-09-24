'#--
'# Copyright (c) 2006-2007 Luis Lavena, Multimedia systems
'#
'# This source code is released under the MIT License.
'# See MIT-LICENSE file for details
'#++

#ifndef __BOOLEAN_BI__
#define __BOOLEAN_BI__

#undef BOOLEAN
type BOOLEAN as byte
#undef FALSE
const FALSE as byte = 0
#undef TRUE
const TRUE as byte = not FALSE

#endif ' __BOOLEAN_BI__