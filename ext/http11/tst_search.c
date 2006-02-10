
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

void *tst_search(unsigned char *key, struct tst *tst, int *prefix_len)
{
  struct node *current_node;
  void *longest_match = NULL;
  int key_index;
  
  assert(key != NULL && "key can't be NULL");
  assert(tst != NULL && "tst can't be NULL");
  
  if(key[0] == 0)
    return NULL;
  
  if(tst->head[(int)key[0]] == NULL)
    return NULL;

  
  if(prefix_len) *prefix_len = 0;
  current_node = tst->head[(int)key[0]];
  key_index = 1;
  
  while (current_node != NULL)
    {
      if(key[key_index] == current_node->value)
	{
	  if(current_node->value == 0) {
	    if(prefix_len) *prefix_len = key_index;
	    return current_node->middle;
	  } else {
	    current_node = current_node->middle;
	    if(current_node && current_node->value == 0) {
	      if(prefix_len) *prefix_len = key_index+1;
	      longest_match = current_node->middle;
	    }

            key_index++;
	    continue;
	  }
	}
      else if( ((current_node->value == 0) && (key[key_index] < 64)) ||
	       ((current_node->value != 0) && (key[key_index] <
					       current_node->value)) )
	{
	  if(current_node->value == 0) {
	    if(prefix_len) *prefix_len = key_index;
	    longest_match = current_node->middle;
	  }
	  current_node = current_node->left;
	  continue;
	}
      else
	{
	  if(current_node->value == 0) {
	    if(prefix_len) *prefix_len = key_index;
	    longest_match = current_node->middle;
	  }
	  current_node = current_node->right;
	  continue;
	}
    }
  
  return longest_match;
}
