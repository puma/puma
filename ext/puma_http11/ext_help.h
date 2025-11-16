#ifndef ext_help_h
#define ext_help_h

#define RAISE_NOT_NULL(T) if(T == NULL) rb_raise(rb_eArgError, "%s", "NULL found for " # T " when shouldn't be.");
#define DATA_GET(from,type,data_type,name) TypedData_Get_Struct(from,type,data_type,name); RAISE_NOT_NULL(name);
#define ARRAY_SIZE(x) (sizeof(x)/sizeof(x[0]))

#ifdef DEBUG
#define TRACE()  fprintf(stderr, "> %s:%d:%s\n", __FILE__, __LINE__, __FUNCTION__)
#else
#define TRACE() 
#endif

#endif
