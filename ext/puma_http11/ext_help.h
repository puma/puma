#ifndef ext_help_h
#define ext_help_h

#define ARRAY_SIZE(x) (sizeof(x)/sizeof(x[0]))

#ifdef DEBUG
#define TRACE()  fprintf(stderr, "> %s:%d:%s\n", __FILE__, __LINE__, __FUNCTION__)
#else
#define TRACE() 
#endif

#endif
