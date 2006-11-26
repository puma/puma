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

static VALUE avoid_mem_pools;

#ifndef USE_MEM_POOLS
#define USE_MEM_POOLS !RTEST(avoid_mem_pools)
#endif

static VALUE rb_cMutex;
static VALUE rb_cConditionVariable;
static VALUE rb_eThreadError;
static VALUE rb_cQueue;
static VALUE rb_cSizedQueue;

static VALUE
return_value(value)
  VALUE value;
{
  return value;
}

typedef struct _Entry {
  VALUE value;
  struct _Entry *next;
} Entry;

typedef struct _List {
  Entry *entries;
  Entry *last_entry;
  Entry *entry_pool;
  unsigned long size;
} List;

static void
init_list(list)
  List *list;
{
  list->entries = NULL;
  list->last_entry = NULL;
  list->entry_pool = NULL;
  list->size = 0;
}

static void
mark_list(list)
  List *list;
{
  Entry *entry;
  for ( entry = list->entries ; entry ; entry = entry->next ) {
    rb_gc_mark(entry->value);
  }
}

static void
free_entries(first)
  Entry *first;
{
  Entry *next;
  while (first) {
    next = first->next;
    free(first);
    first = next;
  }
}

static void
finalize_list(list)
  List *list;
{
  free_entries(list->entries);
  free_entries(list->entry_pool);
}

static void
push_list(list, value)
  List *list;
  VALUE value;
{
  Entry *entry;

  if (list->entry_pool) {
    entry = list->entry_pool;
    list->entry_pool = entry->next;
  } else {
    entry = (Entry *)malloc(sizeof(Entry));
  }

  entry->value = value;
  entry->next = NULL;

  if (list->last_entry) {
    list->last_entry->next = entry;
  } else {
    list->entries = entry;
  }
  list->last_entry = entry;

  ++list->size;
}

static VALUE
shift_list(list)
  List *list;
{
  Entry *entry;
  VALUE value;

  entry = list->entries;
  if (!entry) return Qundef;

  list->entries = entry->next;
  if ( entry == list->last_entry ) {
    list->last_entry = NULL;
  }

  --list->size;

  value = entry->value;
  if (USE_MEM_POOLS) {
    entry->next = list->entry_pool;
    list->entry_pool = entry;
  } else {
    fprintf(stderr, "DEBUG: freeing entry\n");
    free(entry);
  }

  return value;
}

static void
clear_list(list)
  List *list;
{
  if (list->last_entry) {
    if (USE_MEM_POOLS) {
      list->last_entry->next = list->entry_pool;
      list->entry_pool = list->entries;
    } else {
      free_entries(list->entries);
    }
    list->entries = NULL;
    list->last_entry = NULL;
    list->size = 0;
  }
}

static VALUE
wake_one(list)
  List *list;
{
  VALUE waking;

  waking = Qnil;
  while ( list->entries && !RTEST(waking) ) {
    waking = rb_rescue2(rb_thread_wakeup, shift_list(list),
                        return_value, Qnil, rb_eThreadError, 0);
  }

  return waking;
}

static VALUE
wake_all(list)
  List *list;
{
  while (list->entries) {
    wake_one(list);
  }
  return Qnil;
}

typedef struct _Mutex {
  VALUE owner;
  List waiting;
} Mutex;

static void
mark_mutex(mutex)
  Mutex *mutex;
{
  rb_gc_mark(mutex->owner);
  mark_list(&mutex->waiting);
}

static void
finalize_mutex(mutex)
  Mutex *mutex;
{
  finalize_list(&mutex->waiting);
}

static void
free_mutex(mutex)
  Mutex *mutex;
{
  if (mutex->waiting.entries) {
    rb_bug("mutex %p freed with thread(s) waiting", mutex);
  }
  finalize_mutex(mutex);
  free(mutex);
}

static void
init_mutex(mutex)
  Mutex *mutex;
{
  mutex->owner = Qnil;
  init_list(&mutex->waiting);
}

static VALUE
rb_mutex_alloc(klass)
  VALUE klass;
{
  Mutex *mutex;
  mutex = (Mutex *)malloc(sizeof(Mutex));
  init_mutex(mutex);
  return Data_Wrap_Struct(klass, mark_mutex, free_mutex, mutex);
}

static VALUE
rb_mutex_locked_p(self)
  VALUE self;
{
  Mutex *mutex;
  Data_Get_Struct(self, Mutex, mutex);
  return ( RTEST(mutex->owner) ? Qtrue : Qfalse );
}

static VALUE
rb_mutex_try_lock(self)
  VALUE self;
{
  Mutex *mutex;
  VALUE result;

  Data_Get_Struct(self, Mutex, mutex);

  result = Qfalse;

  rb_thread_critical = Qtrue;
  if (!RTEST(mutex->owner)) {
    mutex->owner = rb_thread_current();
    result = Qtrue;
  }
  rb_thread_critical = Qfalse;

  return result;
}

static void
lock_mutex(mutex)
  Mutex *mutex;
{
  VALUE current;
  current = rb_thread_current();

  rb_thread_critical = Qtrue;

  while (RTEST(mutex->owner)) {
    if ( mutex->owner == current ) {
      rb_thread_critical = Qfalse;
      rb_raise(rb_eThreadError, "deadlock; recursive locking");
    }

    push_list(&mutex->waiting, current);
    rb_thread_stop();

    rb_thread_critical = Qtrue;
  }
  mutex->owner = current; 

  rb_thread_critical = Qfalse;
}

static VALUE
rb_mutex_lock(self)
  VALUE self;
{
  Mutex *mutex;
  Data_Get_Struct(self, Mutex, mutex);
  lock_mutex(mutex);
  return self;
}

static VALUE
unlock_mutex_inner(mutex)
  Mutex *mutex;
{
  VALUE waking;

  if (!RTEST(mutex->owner)) {
    return Qundef;
  }
  mutex->owner = Qnil;
  waking = wake_one(&mutex->waiting);

  return waking;
}

static VALUE
set_critical(value)
  VALUE value;
{
  rb_thread_critical = value;
  return Qnil;
}

static VALUE
unlock_mutex(mutex)
  Mutex *mutex;
{
  VALUE waking;

  rb_thread_critical = Qtrue;
  waking = rb_ensure(unlock_mutex_inner, (VALUE)mutex, set_critical, Qfalse);

  if ( waking == Qundef ) {
    return Qfalse;
  }

  if (RTEST(waking)) {
    rb_rescue2(rb_thread_run, waking, return_value, Qnil, rb_eThreadError, 0);
  }

  return Qtrue;
}

static VALUE
rb_mutex_unlock(self)
  VALUE self;
{
  Mutex *mutex;
  Data_Get_Struct(self, Mutex, mutex);

  if (RTEST(unlock_mutex(mutex))) {
    return self;
  } else {
    return Qnil;
  }
}

static VALUE
rb_mutex_exclusive_unlock_inner(mutex)
  Mutex *mutex;
{
  VALUE waking;
  waking = unlock_mutex_inner(mutex);
  rb_yield(Qundef);
  return waking;
}

static VALUE
rb_mutex_exclusive_unlock(self)
  VALUE self;
{
  Mutex *mutex;
  VALUE waking;
  Data_Get_Struct(self, Mutex, mutex);

  rb_thread_critical = Qtrue;
  waking = rb_ensure(rb_mutex_exclusive_unlock_inner, (VALUE)mutex, set_critical, Qfalse);

  if ( waking == Qundef ) {
    return Qnil;
  }

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

typedef struct _ConditionVariable {
  List waiting;
} ConditionVariable;

static void
mark_condvar(condvar)
  ConditionVariable *condvar;
{
  mark_list(&condvar->waiting);
}

static void
finalize_condvar(condvar)
  ConditionVariable *condvar;
{
  finalize_list(&condvar->waiting);
}

static void
free_condvar(condvar)
  ConditionVariable *condvar;
{
  finalize_condvar(condvar);
  free(condvar);
}

static void
init_condvar(condvar)
  ConditionVariable *condvar;
{
  init_list(&condvar->waiting);
}

static VALUE
rb_condvar_alloc(klass)
  VALUE klass;
{
  ConditionVariable *condvar;

  condvar = (ConditionVariable *)malloc(sizeof(ConditionVariable));
  init_condvar(condvar);

  return Data_Wrap_Struct(klass, mark_condvar, free_condvar, condvar);
}

static void
wait_condvar(condvar, mutex)
  ConditionVariable *condvar;
  Mutex *mutex;
{
  rb_thread_critical = Qtrue;
  if (!RTEST(mutex->owner)) {
    rb_thread_critical = Qfalse;
    return;
  }
  if ( mutex->owner != rb_thread_current() ) {
    rb_thread_critical = Qfalse;
    rb_raise(rb_eThreadError, "Not owner");
  }
  mutex->owner = Qnil;
  push_list(&condvar->waiting, rb_thread_current());
  rb_thread_stop();

  lock_mutex(mutex);
}

static VALUE
rb_condvar_wait(VALUE self, VALUE mutex_v)
{
  ConditionVariable *condvar;
  Mutex *mutex;

  if ( CLASS_OF(mutex_v) != rb_cMutex ) {
    rb_raise(rb_eTypeError, "Not a Mutex");
  }
  Data_Get_Struct(self, ConditionVariable, condvar);
  Data_Get_Struct(mutex_v, Mutex, mutex);

  wait_condvar(condvar, mutex);

  return self;
}

static VALUE
rb_condvar_broadcast(self)
  VALUE self;
{
  ConditionVariable *condvar;

  Data_Get_Struct(self, ConditionVariable, condvar);
  
  rb_thread_critical = Qtrue;
  rb_ensure(wake_all, (VALUE)&condvar->waiting, set_critical, Qfalse);
  rb_thread_schedule();

  return self;
}

static void
signal_condvar(condvar)
  ConditionVariable *condvar;
{
  VALUE waking;
  rb_thread_critical = Qtrue;
  waking = rb_ensure(wake_one, (VALUE)&condvar->waiting, set_critical, Qfalse);
  if (RTEST(waking)) {
    rb_rescue2(rb_thread_run, waking, return_value, Qnil, rb_eThreadError, 0);
  }
}

static VALUE
rb_condvar_signal(self)
  VALUE self;
{
  ConditionVariable *condvar;
  Data_Get_Struct(self, ConditionVariable, condvar);
  signal_condvar(condvar);
  return self;
}

typedef struct _Queue {
  Mutex mutex;
  ConditionVariable value_available;
  List values;
} Queue;

static void
mark_queue(queue)
  Queue *queue;
{
  mark_mutex(&queue->mutex);
  mark_condvar(&queue->value_available);
  mark_list(&queue->values);
}

static void
finalize_queue(queue)
  Queue *queue;
{
  finalize_mutex(&queue->mutex);
  finalize_condvar(&queue->value_available);
  finalize_list(&queue->values);
}

static void
free_queue(queue)
  Queue *queue;
{
  finalize_queue(queue);
  free(queue);
}

static void
init_queue(queue)
  Queue *queue;
{
  init_mutex(&queue->mutex);
  init_condvar(&queue->value_available);
  init_list(&queue->values);
}

static VALUE
rb_queue_alloc(klass)
  VALUE klass;
{
  Queue *queue;
  queue = (Queue *)malloc(sizeof(Queue));
  init_queue(queue);
  return Data_Wrap_Struct(klass, mark_queue, free_queue, queue);
}

static VALUE
rb_queue_clear(VALUE self)
{
  Queue *queue;
  Data_Get_Struct(self, Queue, queue);

  lock_mutex(&queue->mutex);
  clear_list(&queue->values);
  unlock_mutex(&queue->mutex);

  return self;
}

static VALUE
rb_queue_empty_p(self)
  VALUE self;
{
  Queue *queue;
  VALUE result;
  Data_Get_Struct(self, Queue, queue);

  lock_mutex(&queue->mutex);
  result = ( ( queue->values.size == 0 ) ? Qtrue : Qfalse );
  unlock_mutex(&queue->mutex);

  return result;
}

static VALUE
rb_queue_length(self)
  VALUE self;
{
  Queue *queue;
  VALUE result;
  Data_Get_Struct(self, Queue, queue);

  lock_mutex(&queue->mutex);
  result = ULONG2NUM(queue->values.size);
  unlock_mutex(&queue->mutex);

  return result;
}

static VALUE
rb_queue_num_waiting(self)
{
  Queue *queue;
  VALUE result;
  Data_Get_Struct(self, Queue, queue);

  lock_mutex(&queue->mutex);
  result = ULONG2NUM(queue->value_available.waiting.size);
  unlock_mutex(&queue->mutex);

  return result;
}

static VALUE
rb_queue_pop(argc, argv, self)
  int argc;
  VALUE *argv;
  VALUE self;
{
  Queue *queue;
  int should_block;
  VALUE result;
  Data_Get_Struct(self, Queue, queue);

  if ( argc == 0 ) {
    should_block = 1;
  } else if ( argc == 1 ) {
    should_block = !RTEST(argv[0]);
  } else {
    rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
  }

  lock_mutex(&queue->mutex);
  if ( !queue->values.entries && !should_block ) {
    unlock_mutex(&queue->mutex);
    rb_raise(rb_eThreadError, "queue empty");
  }

  while (!queue->values.entries) {
    wait_condvar(&queue->value_available, &queue->mutex);
  }

  result = shift_list(&queue->values);
  unlock_mutex(&queue->mutex);

  return result;
}

static VALUE
rb_queue_push(self, value)
  VALUE self;
  VALUE value;
{
  Queue *queue;
  Data_Get_Struct(self, Queue, queue);

  lock_mutex(&queue->mutex);
  push_list(&queue->values, value);
  unlock_mutex(&queue->mutex);
  signal_condvar(&queue->value_available);

  return self;
}

typedef struct _SizedQueue {
  Queue queue;
  ConditionVariable space_available;
  unsigned long capacity;
} SizedQueue;

static void
mark_sized_queue(queue)
  SizedQueue *queue;
{
  mark_queue(&queue->queue);
  mark_condvar(&queue->space_available);
}

static void
free_sized_queue(queue)
  SizedQueue *queue;
{
  finalize_queue(&queue->queue);
  finalize_condvar(&queue->space_available);
  free(queue);
}

static VALUE
rb_sized_queue_alloc(klass)
  VALUE klass;
{
  SizedQueue *queue;
  queue = (SizedQueue *)malloc(sizeof(SizedQueue));

  init_queue(&queue->queue);
  init_condvar(&queue->space_available);
  queue->capacity = 0;

  return Data_Wrap_Struct(klass, mark_sized_queue, free_sized_queue, queue);
}

static VALUE
rb_sized_queue_clear(self)
  VALUE self;
{
  SizedQueue *queue;
  Data_Get_Struct(self, SizedQueue, queue);
  rb_queue_clear(self);
  signal_condvar(&queue->space_available);
  return self;
}

static VALUE
rb_sized_queue_max(self)
  VALUE self;
{
  SizedQueue *queue;
  VALUE result;
  Data_Get_Struct(self, SizedQueue, queue);

  lock_mutex(&queue->queue.mutex);
  result = ULONG2NUM(queue->capacity);
  unlock_mutex(&queue->queue.mutex);

  return result;
}

static VALUE
rb_sized_queue_max_set(self, value)
  VALUE self;
  VALUE value;
{
  SizedQueue *queue;
  unsigned long new_capacity;
  unsigned long difference;
  Data_Get_Struct(self, SizedQueue, queue);

  new_capacity = NUM2ULONG(value);

  lock_mutex(&queue->queue.mutex);
  if ( new_capacity > queue->capacity ) {
    difference = new_capacity - queue->capacity;
  } else {
    difference = 0;
  }
  queue->capacity = new_capacity;
  unlock_mutex(&queue->queue.mutex);

  for ( ; difference > 0 ; --difference ) {
    signal_condvar(&queue->space_available);
  }

  return self;
}

static VALUE
rb_sized_queue_initialize(self, max)
  VALUE self;
  VALUE max;
{
  return rb_sized_queue_max_set(self, max);
}

static VALUE
rb_sized_queue_num_waiting(self)
  VALUE self;
{
  SizedQueue *queue;
  VALUE result;
  Data_Get_Struct(self, SizedQueue, queue);

  lock_mutex(&queue->queue.mutex);
  result = ULONG2NUM(queue->queue.value_available.waiting.size +
                     queue->space_available.waiting.size);
  unlock_mutex(&queue->queue.mutex);

  return result;
}

static VALUE
rb_sized_queue_pop(argc, argv, self)
  int argc;
  VALUE *argv;
  VALUE self;
{
  SizedQueue *queue;
  VALUE result;
  Data_Get_Struct(self, SizedQueue, queue);

  result = rb_queue_pop(argc, argv, self);
  signal_condvar(&queue->space_available);

  return result;
}

static VALUE
rb_sized_queue_push(self, value)
  VALUE self;
  VALUE value;
{
  SizedQueue *queue;
  Data_Get_Struct(self, SizedQueue, queue);

  lock_mutex(&queue->queue.mutex);
  while ( queue->queue.values.size >= queue->capacity ) {
    wait_condvar(&queue->space_available, &queue->queue.mutex);
  }
  push_list(&queue->queue.values);
  unlock_mutex(&queue->queue.mutex);
  
  return self;
}

void
Init_fastthread()
{
  avoid_mem_pools = rb_gv_get("$fastthread_avoid_mem_pools");
  rb_global_variable(&avoid_mem_pools);
  rb_define_variable("$fastthread_avoid_mem_pools", &avoid_mem_pools);

  if (!RTEST(rb_require("thread"))) {
    rb_raise(rb_eRuntimeError, "fastthread must be required before thread");
  }

  rb_eThreadError = rb_const_get(rb_cObject, rb_intern("ThreadError"));

  rb_cMutex = rb_define_class("Mutex", rb_cObject);
  rb_define_alloc_func(rb_cMutex, rb_mutex_alloc);
  rb_define_method(rb_cMutex, "initialize", return_value, 0);
  rb_define_method(rb_cMutex, "locked?", rb_mutex_locked_p, 0);
  rb_define_method(rb_cMutex, "try_lock", rb_mutex_try_lock, 0);
  rb_define_method(rb_cMutex, "lock", rb_mutex_lock, 0);
  rb_define_method(rb_cMutex, "unlock", rb_mutex_unlock, 0);
  rb_define_method(rb_cMutex, "exclusive_unlock", rb_mutex_exclusive_unlock, 0);
  rb_define_method(rb_cMutex, "synchronize", rb_mutex_synchronize, 0);

  rb_cConditionVariable = rb_define_class("ConditionVariable", rb_cObject);
  rb_define_alloc_func(rb_cConditionVariable, rb_condvar_alloc);
  rb_define_method(rb_cConditionVariable, "initialize", return_value, 0);
  rb_define_method(rb_cConditionVariable, "wait", rb_condvar_wait, 1);
  rb_define_method(rb_cConditionVariable, "broadcast", rb_condvar_broadcast, 0);
  rb_define_method(rb_cConditionVariable, "signal", rb_condvar_signal, 0);

  rb_cQueue = rb_define_class("Queue", rb_cObject);
  rb_define_alloc_func(rb_cQueue, rb_queue_alloc);
  rb_define_method(rb_cQueue, "initialize", return_value, 0);
  rb_define_method(rb_cQueue, "clear", rb_queue_clear, 0);
  rb_define_method(rb_cQueue, "empty?", rb_queue_empty_p, 0);
  rb_define_method(rb_cQueue, "length", rb_queue_length, 0);
  rb_define_method(rb_cQueue, "num_waiting", rb_queue_num_waiting, 0);
  rb_define_method(rb_cQueue, "pop", rb_queue_pop, -1);
  rb_define_method(rb_cQueue, "push", rb_queue_push, 1);
  rb_alias(rb_cQueue, rb_intern("<<"), rb_intern("push"));
  rb_alias(rb_cQueue, rb_intern("deq"), rb_intern("pop"));
  rb_alias(rb_cQueue, rb_intern("shift"), rb_intern("pop"));
  rb_alias(rb_cQueue, rb_intern("size"), rb_intern("length"));

  rb_cSizedQueue = rb_define_class("SizedQueue", rb_cQueue);
  rb_define_alloc_func(rb_cSizedQueue, rb_sized_queue_alloc);
  rb_define_method(rb_cSizedQueue, "initialize", rb_sized_queue_initialize, 1);
  rb_define_method(rb_cSizedQueue, "clear", rb_sized_queue_clear, 0);
  rb_define_method(rb_cSizedQueue, "max", rb_sized_queue_max, 0);
  rb_define_method(rb_cSizedQueue, "max=", rb_sized_queue_max_set, 1);
  rb_define_method(rb_cSizedQueue, "num_waiting",
                   rb_sized_queue_num_waiting, 0);
  rb_define_method(rb_cSizedQueue, "pop", rb_sized_queue_pop, -1);
  rb_define_method(rb_cSizedQueue, "push", rb_sized_queue_push, 1);
  rb_alias(rb_cQueue, rb_intern("<<"), rb_intern("push"));
  rb_alias(rb_cQueue, rb_intern("deq"), rb_intern("pop"));
  rb_alias(rb_cQueue, rb_intern("shift"), rb_intern("pop"));
}

