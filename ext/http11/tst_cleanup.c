
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>

void tst_cleanup(struct tst *tst)
{
   struct node_lines *current_line;
   struct node_lines *next_line;

   next_line = tst->node_lines;

   do
   {
      current_line = next_line;
      next_line = current_line->next;
      free(current_line->node_line);
      free(current_line);
   }
   while(next_line != NULL);

   free(tst);
}

