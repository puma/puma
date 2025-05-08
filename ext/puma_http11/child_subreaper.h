#ifndef CHILD_SUBREAPER_H
#define CHILD_SUBREAPER_H 1

#include "ruby.h"
#ifdef HAVE_CONST_PR_SET_CHILD_SUBREAPER
#include <sys/prctl.h>
static VALUE child_subreaper_enable(VALUE module) {
  if (prctl(PR_SET_CHILD_SUBREAPER, 1) < 0) {
    rb_sys_fail("prctl(2) PR_SET_CHILD_SUBREAPER");
  }
  return Qtrue;
}
#else
static VALUE child_subreaper_enable(VALUE module) {
  return Qfalse;
}
#endif

#endif /* CHILD_SUBREAPER_H */
