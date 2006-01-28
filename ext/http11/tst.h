

struct node
{
   unsigned char value;
   struct node *left;
   struct node *middle;
   struct node *right;
};

struct tst
{
   int node_line_width;
   struct node_lines *node_lines;
   struct node *free_list;
   struct node *head[127];
};

struct node_lines
{
   struct node *node_line;
   struct node_lines *next;
};

enum tst_constants
{
   TST_OK, TST_ERROR, TST_NULL_KEY, TST_DUPLICATE_KEY, TST_REPLACE
};

struct tst *tst_init(int node_line_width);

int tst_insert(unsigned char *key, void *data, struct tst *tst, int option, void **exist_ptr);

void *tst_search(unsigned char *key, struct tst *tst, int *prefix_len);

void *tst_delete(unsigned char *key, struct tst *tst);

void tst_cleanup(struct tst *tst);


