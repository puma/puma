
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>

void *tst_delete(unsigned char *key, struct tst *tst)
{
   struct node *current_node;
   struct node *current_node_parent;
   struct node *last_branch;
   struct node *last_branch_parent;
   struct node *next_node;
   struct node *last_branch_replacement;
   struct node *last_branch_dangling_child;
   int key_index;

   
   if(key[0] == 0)
      return NULL;
   if(tst->head[(int)key[0]] == NULL)
      return NULL;
   
   last_branch = NULL;
   last_branch_parent = NULL;
   current_node = tst->head[(int)key[0]];
   current_node_parent = NULL;
   key_index = 1;
   while(current_node != NULL)
   {
      if(key[key_index] == current_node->value)
      {
         
         if( (current_node->left != NULL) || (current_node->right != NULL) )
         {
            last_branch = current_node;
            last_branch_parent = current_node_parent;
         }
         if(key[key_index] == 0)
            break;
         else
         {
            current_node_parent = current_node;
            current_node = current_node->middle;
            key_index++;
            continue;
         }
      }
      else if( ((current_node->value == 0) && (key[key_index] < 64)) ||
         ((current_node->value != 0) && (key[key_index] <
         current_node->value)) )
      {
         last_branch_parent = current_node;
         current_node_parent = current_node;
         current_node = current_node->left;
         last_branch = current_node;
         continue;
      }
      else
      {
         last_branch_parent = current_node;
         current_node_parent = current_node;
         current_node = current_node->right;
         last_branch = current_node;
         continue;
      }
   
   }
   if(current_node == NULL)
      return NULL;
   
   if(last_branch == NULL)
   {
      
         next_node = tst->head[(int)key[0]];
         tst->head[(int)key[0]] = NULL;
   }
   else if( (last_branch->left == NULL) && (last_branch->right == NULL) )
   {
      
      if(last_branch_parent->left == last_branch)
         last_branch_parent->left = NULL;
      else
         last_branch_parent->right = NULL;
      
      next_node = last_branch;
   }
   else
   {
      
      if( (last_branch->left != NULL) && (last_branch->right != NULL) )
      {
         last_branch_replacement = last_branch->right;
         last_branch_dangling_child = last_branch->left;
      }
      else if(last_branch->right != NULL)
      {
         last_branch_replacement = last_branch->right;
         last_branch_dangling_child = NULL;
      }
      else
      {
         last_branch_replacement = last_branch->left;
         last_branch_dangling_child = NULL;
      }
      
      if(last_branch_parent == NULL)
         tst->head[(int)key[0]]=last_branch_replacement;
      else
      {
         if (last_branch_parent->left == last_branch)
            last_branch_parent->left = last_branch_replacement;
         else if (last_branch_parent->right == last_branch)
            last_branch_parent->right = last_branch_replacement;
         else
            last_branch_parent->middle = last_branch_replacement;
      }
      
      if(last_branch_dangling_child != NULL)
      {
         current_node = last_branch_replacement;
      
         while (current_node->left != NULL)
            current_node = current_node->left;
      
         current_node->left = last_branch_dangling_child;
      }
      
      next_node = last_branch;
   }
   
   do
   {
      current_node = next_node;
      next_node = current_node->middle;
      
      current_node->left = NULL;
      current_node->right = NULL;
      current_node->middle = tst->free_list;
      tst->free_list = current_node;
   }
   while(current_node->value != 0);
   
   return next_node;
   
}

