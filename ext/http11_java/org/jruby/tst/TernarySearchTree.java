/*
 * See LICENSE file.
 */
/**
 * $Id: $
 */
package org.jruby.tst;

/**
 * @author <a href="mailto:ola.bini@ki.se">Ola Bini</a>
 * @version $Revision: $
 */
public class TernarySearchTree {
    public final static int TST_OK = 0x1;
    public final static int TST_ERROR = 0x2;
    public final static int TST_NULL_KEY = 0x4;
    public final static int TST_DUPLICATE_KEY = 0x8;
    public final static int TST_REPLACE = 0x10;

    public int node_line_width;
    public NodeLines node_lines;
    public Node free_list;
    public Node[] head = new Node[127];

    public TernarySearchTree(final int width) {
        this.node_lines = new NodeLines();
        this.node_line_width = width;

        this.node_lines.next = null;
        this.node_lines.node_line = new Node[width];
        for(int i=0;i<width;i++) {
            this.node_lines.node_line[i] = new Node();
        }

        Node current_node = this.node_lines.node_line[0];
        this.free_list = current_node;

        for(int i=1; i<width; i++) {
            current_node.middle = this.node_lines.node_line[i];
            current_node = (Node)current_node.middle;
        }
        current_node.middle = null;
    }

    public int insert(final String key, final Object data, final int option, final Object[] exist_ptr) {
        Node current_node = null;
        Node new_node_tree_begin = null;
        int key_index = 0;
        boolean perform_loop = true;

        if(null == key || key.length() == 0) {
            return TST_NULL_KEY;
        }

        if(this.head[key.charAt(0)] == null) {
            if(this.free_list == null) {
                if(!grow_node_free_list()) {
                    return TST_ERROR;
                }
            }
            this.head[key.charAt(0)] = this.free_list;
            this.free_list = (Node)this.free_list.middle;
            current_node = this.head[key.charAt(0)];
            
            if(key.length() == 1) {
                current_node.value = 0;
                current_node.middle = data;
                return TST_OK;
            } else {
                current_node.value = key.charAt(1);
                perform_loop = false;
            }
        }

        current_node = this.head[key.charAt(0)];
        key_index = 1;
        char curr = 0;
        while(perform_loop) {
            if(key_index < key.length()) {
                curr = key.charAt(key_index);
            } else {
                curr = 0;
            }

            if(curr == current_node.value) {
                if(curr == 0) {
                    if(option == TST_REPLACE) {
                        if(exist_ptr.length > 0) {
                            exist_ptr[0] = current_node.middle;
                        }
                        current_node.middle = data;
                        return TST_OK;
                    } else {
                        if(exist_ptr.length > 0) {
                            exist_ptr[0] = current_node.middle;
                        }
                        return TST_DUPLICATE_KEY;
                    }

                } else {
                    if(current_node.middle == null) {
                        if(this.free_list == null) {
                            if(!grow_node_free_list()) {
                                return TST_ERROR;
                            }
                        }
                        current_node.middle = this.free_list;
                        this.free_list = (Node)this.free_list.middle;
                        new_node_tree_begin = current_node;
                        current_node = (Node)current_node.middle;
                        current_node.value = curr;
                        break;
                    } else {
                        current_node = (Node)current_node.middle;
                        key_index++;
                        continue;
                    }
                }
            }

            if((current_node.value == 0 && curr < 64) ||
               (current_node.value != 0 && curr < current_node.value)) {
                if(current_node.left == null) {
                    if(this.free_list == null) {
                        if(!grow_node_free_list()) {
                            return TST_ERROR;
                        }
                    }
                    current_node.left = this.free_list;
                    this.free_list = (Node)this.free_list.middle;
                    new_node_tree_begin = current_node;
                    current_node = current_node.left;
                    current_node.value = curr;
                    if(curr == 0) {
                        current_node.middle = data;
                        return TST_OK;
                    } else {
                        break;
                    }
                } else {
                    current_node = current_node.left;
                    continue;
                }
            } else {
                if(current_node.right == null) {
                    if(this.free_list == null) {
                        if(!grow_node_free_list()) {
                            return TST_ERROR;
                        }
                    }
                    current_node.right = this.free_list;
                    this.free_list = (Node)this.free_list.middle;
                    new_node_tree_begin = current_node;
                    current_node = current_node.right;
                    current_node.value = curr;
                    break;
                } else {
                    current_node = current_node.right;
                    continue;
                }
            }
        }
        
        do {
            key_index++;
            if(key_index < key.length()) {
                curr = key.charAt(key_index);
            } else {
                curr = 0;
            }

            if(this.free_list == null) {
                if(!grow_node_free_list()) {
                    current_node = (Node)new_node_tree_begin.middle;
                    while(current_node.middle != null) {
                        current_node = (Node)current_node.middle;
                    }
                    current_node.middle = this.free_list;
                    this.free_list = (Node)new_node_tree_begin.middle;
                    new_node_tree_begin.middle = null;
                    return TST_ERROR;
                }
            }
            
            if(this.free_list == null) {
                if(!grow_node_free_list()) {
                    return TST_ERROR;
                }
            }
            current_node.middle = this.free_list;
            this.free_list = (Node)this.free_list.middle;
            current_node = (Node)current_node.middle;

            current_node.value = curr;
        } while(curr != 0);
        
        current_node.middle = data;
        return TST_OK;
    }

    public Object search(final String key, final int[] prefix_len) {
        Node current_node = null;
        Object longest_match = null;
        int key_index = 0;

        if(key == null) {
            throw new IllegalArgumentException("key can't be null");
        }

        if(key.length() == 0 || this.head[key.charAt(0)] == null) {
            return null;
        }

        if(prefix_len.length > 0) {
            prefix_len[0] = 0;
        }

        current_node = this.head[key.charAt(0)];
        key_index = 1;

        char curr = 0;
        while(null != current_node) {
            if(key_index < key.length()) {
                curr = key.charAt(key_index);
            } else {
                curr = 0;
            }

            if(curr == current_node.value) {
                if(current_node.value == 0) {
                    if(prefix_len.length>0) {
                        prefix_len[0] = key_index;
                    }
                    return current_node.middle;
                } else {
                    current_node = (Node)current_node.middle;
                    if(current_node != null && current_node.value == 0) {
                        if(prefix_len.length>0) {
                            prefix_len[0] = key_index+1;
                        }
                        longest_match = current_node.middle;
                    }
                    key_index++;
                    continue;
                }
            } else if((current_node.value == 0 && curr < 64) ||
                      (current_node.value != 0 && curr < current_node.value)) {
                if(current_node.value == 0) {
                    if(prefix_len.length>0) {
                        prefix_len[0] = key_index;
                    }
                    longest_match = current_node.middle;
                }
                current_node = current_node.left;
                continue;
            } else {
                if(current_node.value == 0) {
                    if(prefix_len.length>0) {
                        prefix_len[0] = key_index;
                    }
                    longest_match = current_node.middle;
                }
                current_node = current_node.right;
                continue;
            }
        }

        return longest_match;
    }

    public Object delete(final String key) {
        Node current_node = null;
        Node current_node_parent = null;
        Node last_branch = null;
        Node last_branch_parent = null;
        Object next_node = null;
        Node last_branch_replacement = null;
        Node last_branch_dangling_child = null;
        int key_index = 1;
        
        if(key.length() == 0 || this.head[key.charAt(0)] == null) {
            return null;
        }
   
        current_node = this.head[key.charAt(0)];

        char curr = 0;
        while(null != current_node) {
            if(key_index < key.length()) {
                curr = key.charAt(key_index);
            } else {
                curr = 0;
            }
            if(curr == current_node.value) {
                if(current_node.left != null || current_node.right != null) {
                    last_branch = current_node;
                    last_branch_parent = current_node_parent;
                }
                if(curr == 0) {
                    break;
                }
                current_node_parent = current_node;
                current_node = (Node)current_node.middle;
                key_index++;
                continue;
            } else if((current_node.value == 0 && curr < 64) ||
                      (current_node.value != 0&& curr < current_node.value)) {
                last_branch_parent = current_node;
                current_node_parent = current_node;
                current_node = current_node.left;
                last_branch = current_node;
                continue;
            } else {
                last_branch_parent = current_node;
                current_node_parent = current_node;
                current_node = current_node.right;
                last_branch = current_node;
                continue;
            }
        }

        if(null == current_node) {
            return null;
        }
        
        if(null == last_branch) {
            next_node = this.head[key.charAt(0)];
            this.head[key.charAt(0)] = null;
        } else if(last_branch.left == null && last_branch.right == null) {
            if(last_branch_parent.left == last_branch) {
                last_branch_parent.left = null;
            } else {
                last_branch_parent.right = null;
            }
            next_node = last_branch;
        } else {
            if(last_branch.left != null && last_branch.right != null) {
                last_branch_replacement = last_branch.right;
                last_branch_dangling_child = last_branch.left;
            } else if(last_branch.right != null) {
                last_branch_replacement = last_branch.right;
                last_branch_dangling_child = null;
            } else {
                last_branch_replacement = last_branch.left;
                last_branch_dangling_child = null;
            }

            if(last_branch_parent == null) {
                this.head[key.charAt(0)] = last_branch_replacement;
            } else {
                if(last_branch_parent.left == last_branch) {
                    last_branch_parent.left = last_branch_replacement;
                } else if(last_branch_parent.right == last_branch) {
                    last_branch_parent.right = last_branch_replacement;
                } else {
                    last_branch_parent.middle = last_branch_replacement;
                }
            }
            
            if(last_branch_dangling_child != null) {
                current_node = last_branch_replacement;
                while(current_node.left != null) {
                    current_node = current_node.left;
                }
                current_node.left = last_branch_dangling_child;
            }

            next_node = last_branch;
        }
   
        do {
            current_node = (Node)next_node;
            next_node = current_node.middle;
            current_node.left = null;
            current_node.right = null;
            current_node.middle = this.free_list;
            this.free_list = current_node;
        } while(current_node.value != 0);


        return next_node;
    }

    public boolean grow_node_free_list() {
        Node current_node = null;
        NodeLines new_line = null;

        new_line = new NodeLines();

        new_line.node_line = new Node[this.node_line_width];
        for(int i=0;i<this.node_line_width;i++) {
            new_line.node_line[i] = new Node();
        }

        new_line.next = this.node_lines;
        this.node_lines = new_line;

        current_node = this.node_lines.node_line[0];
        this.free_list = current_node;
        for(int i=1;i<this.node_line_width;i++) {
            current_node.middle = this.node_lines.node_line[i];
            current_node = (Node)current_node.middle;
        }
        current_node.middle = null;

        return true;
    }


    public static void main(final String[] args) {
        final TernarySearchTree tst = new TernarySearchTree(30);
        int ret = tst.insert("fOO","VAL1",0, new Object[0]);
        System.err.println("ret: " + ret);
        ret = tst.insert("bar","VAL2",0, new Object[0]);
        System.err.println("ret: " + ret);
        ret = tst.insert("baz","VAL3",0, new Object[0]);
        System.err.println("ret: " + ret);
        ret = tst.insert("zydsfgfd","VAL4",0, new Object[0]);
        System.err.println("ret: " + ret);
        ret = tst.insert("1242","VAL5",0, new Object[0]);
        System.err.println("ret: " + ret);

        Object val = tst.delete("fOO");
        System.err.println("del: " + val);

        int[] pref_len = new int[1];
        pref_len[0] = 0;
        val = tst.search("ba",pref_len);
        System.err.println("search: " + val + " pref_len: " + pref_len[0]);
        val = tst.search("bar",pref_len);
        System.err.println("search: " + val + " pref_len: " + pref_len[0]);
    }
}// TernarySearchTree
