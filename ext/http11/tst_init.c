
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>

struct tst *tst_init(int width)
{
   struct tst *tst;
   struct node *current_node;
   int i;


if((tst = (struct tst *) calloc(1, sizeof(struct tst))) == NULL)
   return NULL;

if ((tst->node_lines = (struct node_lines *) calloc(1, sizeof(struct node_lines))) == NULL)
{
   free(tst);
   return NULL;
}

tst->node_line_width = width;
tst->node_lines->next = NULL;
if ((tst->node_lines->node_line = (struct node *) calloc(width, sizeof(struct node))) == NULL)
{
   free(tst->node_lines);
   free(tst);
   return NULL;
}

current_node = tst->node_lines->node_line;
tst->free_list = current_node;
for (i = 1; i < width; i++)
{
   current_node->middle = &(tst->node_lines->node_line[i]);
   current_node = current_node->middle;
}
current_node->middle = NULL;
return tst;
}

