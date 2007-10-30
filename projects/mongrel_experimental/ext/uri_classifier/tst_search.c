
#include "tst.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>


void *tst_search(const unsigned char *key, struct tst *tst, int option,
		 unsigned int *match_len)
{
    struct node *current_node;
    struct node *longest_match = NULL;
    unsigned int longest_match_len = 0;
    int key_index;

    assert(key != NULL && "key can't be NULL");
    assert(tst != NULL && "tst can't be NULL");

    if (key[0] == 0)
	return NULL;

    if (tst->head[(int) key[0]] == NULL)
	return NULL;

    if (match_len)
	*match_len = 0;

    current_node = tst->head[(int) key[0]];
    key_index = 1;

    while (current_node != NULL) {
	if (key[key_index] == current_node->value) {
	    if (current_node->value == 0) {
		if (match_len)
		    *match_len = key_index;
		return current_node->middle;
	    } else {
		current_node = current_node->middle;
		key_index++;
		continue;
	    }
	} else {
	    if (current_node->value == 0) {
		if (option & TST_LONGEST_MATCH) {
		    longest_match = current_node->middle;
		    longest_match_len = key_index;
		}

		if (key[key_index] < 64) {
		    current_node = current_node->left;
		    continue;
		} else {
		    current_node = current_node->right;
		    continue;
		}
	    } else {
		if (key[key_index] < current_node->value) {
		    current_node = current_node->left;
		    continue;
		} else {
		    current_node = current_node->right;
		    continue;
		}
	    }
	}
    }

    if (match_len)
	*match_len = longest_match_len;

    return longest_match;

}
