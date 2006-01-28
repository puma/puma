
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>


int tst_grow_node_free_list(struct tst *tst);
int tst_insert(unsigned char *key, void *data, struct tst *tst, int option, void **exist_ptr)
{
   struct node *current_node;
   struct node *new_node_tree_begin = NULL;
   int key_index;
   int perform_loop = 1;

   
   if (key == NULL)
      return TST_NULL_KEY;
   
   if(key[0] == 0)
      return TST_NULL_KEY;
   
   if(tst->head[(int)key[0]] == NULL)
   {
      
      if(tst->free_list == NULL)
      {
         if(tst_grow_node_free_list(tst) != 1)
            return TST_ERROR;
      }
      tst->head[(int)key[0]] = tst->free_list;
      
      tst->free_list = tst->free_list->middle;
      current_node = tst->head[(int)key[0]];
      current_node->value = key[1];
      if(key[1] == 0)
      {
         current_node->middle = data;
         return TST_OK;
      }
      else
         perform_loop = 0;
   }
   
   current_node = tst->head[(int)key[0]];
   key_index = 1;
   while(perform_loop == 1)
   {
      if(key[key_index] == current_node->value)
      {
         
         if(key[key_index] == 0)
         {
            if (option == TST_REPLACE)
            {
               if (exist_ptr != NULL)
                  *exist_ptr = current_node->middle;
         
               current_node->middle = data;
               return TST_OK;
            }
            else
            {
               if (exist_ptr != NULL)
                  *exist_ptr = current_node->middle;
               return TST_DUPLICATE_KEY;
            }
         }
         else
         {
            if(current_node->middle == NULL)
            {
               
               if(tst->free_list == NULL)
               {
                  if(tst_grow_node_free_list(tst) != 1)
                     return TST_ERROR;
               }
               current_node->middle = tst->free_list;
               
               tst->free_list = tst->free_list->middle;
               new_node_tree_begin = current_node;
               current_node = current_node->middle;
               current_node->value = key[key_index];
               break;
            }
            else
            {
               current_node = current_node->middle;
               key_index++;
               continue;
            }
         }
      }
   
      if( ((current_node->value == 0) && (key[key_index] < 64)) ||
         ((current_node->value != 0) && (key[key_index] <
         current_node->value)) )
      {
         
         if (current_node->left == NULL)
         {
            
            if(tst->free_list == NULL)
            {
               if(tst_grow_node_free_list(tst) != 1)
                  return TST_ERROR;
            }
            current_node->left = tst->free_list;
            
            tst->free_list = tst->free_list->middle;
            new_node_tree_begin = current_node;
            current_node = current_node->left;
            current_node->value = key[key_index];
            if(key[key_index] == 0)
            {
               current_node->middle = data;
               return TST_OK;
            }
            else
               break;
         }
         else
         {
            current_node = current_node->left;
            continue;
         }
      }
      else
      {
         
         if (current_node->right == NULL)
         {
            
            if(tst->free_list == NULL)
            {
               if(tst_grow_node_free_list(tst) != 1)
                  return TST_ERROR;
            }
            current_node->right = tst->free_list;
            
            tst->free_list = tst->free_list->middle;
            new_node_tree_begin = current_node;
            current_node = current_node->right;
            current_node->value = key[key_index];
            break;
         }
         else
         {
            current_node = current_node->right;
            continue;
         }
      }
   }
   
   do
   {
      key_index++;
   
      if(tst->free_list == NULL)
      {
         if(tst_grow_node_free_list(tst) != 1)
         {
            current_node = new_node_tree_begin->middle;
   
            while (current_node->middle != NULL)
               current_node = current_node->middle;
   
            current_node->middle = tst->free_list;
            tst->free_list = new_node_tree_begin->middle;
            new_node_tree_begin->middle = NULL;
   
            return TST_ERROR;
         }
      }
   
      
      if(tst->free_list == NULL)
      {
         if(tst_grow_node_free_list(tst) != 1)
            return TST_ERROR;
      }
      current_node->middle = tst->free_list;
      
      tst->free_list = tst->free_list->middle;
      current_node = current_node->middle;
      current_node->value = key[key_index];
   } while(key[key_index] !=0);
   
   current_node->middle = data;
   return TST_OK;
}

