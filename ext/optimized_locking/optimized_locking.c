/*
 * Optimized Ruby Mutex implementation, loosely based on thread.rb by
 * Yukihiro Matsumoto <matz@ruby-lang.org>
 *
 *  Copyright 2006  MenTaLguY <mental@rydia.net>
 *
 * This file is made available under the same terms as Ruby.
 */

#include <ruby.h>
#include <intern.h>
#include <rubysig.h>

static VALUE rb_cOptimizedMutex;
static VALUE rb_eThreadError;

typedef struct _WaitEntry {
  struct _WaitEntry *next;
  VALUE thread;
} WaitEntry;

typedef struct _Mutex {
  VALUE locked;
  WaitEntry *waiting;
  WaitEntry *last_waiting;
  WaitEntry *entry_pool;
} Mutex;

static void
rb_mutex_mark(m)
  Mutex *m;
{
  rb_gc_mark(m->locked);
  WaitEntry *e=m->waiting;
  while (e) {
    rb_gc_mark(e->thread);
    e = e->next;
  }
}

static void
rb_mutex_free(m)
  Mutex *m;
{
  WaitEntry *e;
  if (m->waiting) {
    rb_bug("mutex %p freed with thread(s) waiting", m);
  }
  e = m->entry_pool;
  while (e) {
    WaitEntry *next = e->next;
    free(e);
    e = next;
  }
  free(m);
}

static VALUE
return_value(value)
  VALUE value;
{
  return value;
}

static VALUE
rb_mutex_alloc()
{
  Mutex *m;
  m = (Mutex *)malloc(sizeof(Mutex));
  m->locked = Qfalse;
  m->waiting = NULL;
  m->last_waiting = NULL;
  m->entry_pool = NULL;

  return Data_Wrap_Struct(rb_cOptimizedMutex, rb_mutex_mark, rb_mutex_free, m);
}

static VALUE
rb_mutex_locked_p(self)
  VALUE self;
{
  Mutex *m;
  Data_Get_Struct(self, Mutex, m);
  return ( m->locked ? Qtrue : Qfalse );
}

static VALUE
rb_mutex_try_lock(self)
  VALUE self;
{
  Mutex *m;
  VALUE result;

  Data_Get_Struct(self, Mutex, m);

  result = Qfalse;

  rb_thread_critical = Qtrue;
  if (!RTEST(m->locked)) {
    m->locked = rb_thread_current();
    result = Qtrue;
  }
  rb_thread_critical = Qfalse;

  return result;
}

static VALUE
rb_mutex_lock(self)
  VALUE self;
{
  Mutex *m;
  VALUE current;

  Data_Get_Struct(self, Mutex, m);
  current = rb_thread_current();

  rb_thread_critical = Qtrue;
  while (RTEST(m->locked)) {
    WaitEntry *e;

    if ( m->locked == current ) {
      rb_raise(rb_eThreadError, "deadlock; recursive locking");
    }

    if (m->entry_pool) {
      e = m->entry_pool;
      m->entry_pool = e->next;
    } else {
      e = (WaitEntry *)malloc(sizeof(WaitEntry));
    }

    e->thread = current;
    e->next = NULL;

    if (m->last_waiting) {
      m->last_waiting->next = e;
    } else {
      m->waiting = e;
    }
    m->last_waiting = e;

    rb_thread_stop();
    rb_thread_critical = Qtrue;
  }
  m->locked = current; 
  rb_thread_critical = Qfalse;
  return self;
}

static VALUE
rb_mutex_unlock(self)
  VALUE self;
{
  Mutex *m;
  VALUE current;
  VALUE waking;
  Data_Get_Struct(self, Mutex, m);
  current = rb_thread_current();
  if (!RTEST(m->locked)) {
    return Qnil;
  }
  rb_thread_critical = Qtrue;
  m->locked = Qfalse;
  waking = Qnil;
  while ( m->waiting && !RTEST(waking) ) {
    WaitEntry *e;
    e = m->waiting;
    m->waiting = e->next;
    if (!m->waiting) {
      m->last_waiting = NULL;
    }
    e->next = m->entry_pool;
    m->entry_pool = e;
    waking = rb_rescue2(rb_thread_wakeup, e->thread, return_value, Qnil, rb_eThreadError, 0);
  }
  rb_thread_critical = Qfalse;
  if (RTEST(waking)) {
    rb_rescue2(rb_thread_run, waking, return_value, Qnil, rb_eThreadError, 0);
  }
  return self;
}

static VALUE
rb_mutex_synchronize(self)
  VALUE self;
{
  rb_mutex_lock(self);
  return rb_ensure(rb_yield, Qundef, rb_mutex_unlock, self);
}

void
Init_optimized_locking()
{
  rb_require("thread");
  rb_eThreadError = rb_const_get(rb_cObject, rb_intern("ThreadError"));
  rb_cOptimizedMutex = rb_define_class("OptimizedMutex", rb_cObject);
  rb_define_alloc_func(rb_cOptimizedMutex, rb_mutex_alloc);
  rb_define_method(rb_cOptimizedMutex, "locked?", rb_mutex_locked_p, 0);
  rb_define_method(rb_cOptimizedMutex, "try_lock", rb_mutex_try_lock, 0);
  rb_define_method(rb_cOptimizedMutex, "lock", rb_mutex_lock, 0);
  rb_define_method(rb_cOptimizedMutex, "unlock", rb_mutex_unlock, 0);
  rb_define_method(rb_cOptimizedMutex, "synchronize", rb_mutex_synchronize, 0);
}

