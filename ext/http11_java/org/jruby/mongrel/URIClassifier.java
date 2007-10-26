/***** BEGIN LICENSE BLOCK *****
 * Version: CPL 1.0/GPL 2.0/LGPL 2.1
 *
 * The contents of this file are subject to the Common Public
 * License Version 1.0 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.eclipse.org/legal/cpl-v10.html
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * Copyright (C) 2007 Ola Bini <ola@ologix.com>
 * 
 * Alternatively, the contents of this file may be used under the terms of
 * either of the GNU General Public License Version 2 or later (the "GPL"),
 * or the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the CPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the CPL, the GPL or the LGPL.
 ***** END LICENSE BLOCK *****/
package org.jruby.mongrel;

import org.jruby.Ruby;
import org.jruby.RubyArray;
import org.jruby.RubyClass;
import org.jruby.RubyHash;
import org.jruby.RubyModule;
import org.jruby.RubyObject;
import org.jruby.RubyString;

import org.jruby.runtime.Block;
import org.jruby.runtime.CallbackFactory;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.builtin.IRubyObject;

import org.jruby.tst.TernarySearchTree;

/**
 * @author <a href="mailto:ola.bini@ki.se">Ola Bini</a>
 */
public class URIClassifier extends RubyObject {
    public final static int TRIE_INCREASE = 30;

    private static ObjectAllocator ALLOCATOR = new ObjectAllocator() {
        public IRubyObject allocate(Ruby runtime, RubyClass klass) {
            return new URIClassifier(runtime, klass);
        }
    };

    public static void createURIClassifier(Ruby runtime, RubyModule mMongrel) {
        RubyClass cURIClassifier = mMongrel.defineClassUnder("URIClassifier",runtime.getObject(),ALLOCATOR);
        CallbackFactory cf = runtime.callbackFactory(URIClassifier.class);
        cURIClassifier.defineFastMethod("initialize",cf.getFastMethod("initialize"));
        cURIClassifier.defineFastMethod("register",cf.getFastMethod("register",IRubyObject.class,IRubyObject.class));
        cURIClassifier.defineFastMethod("unregister",cf.getFastMethod("unregister",IRubyObject.class));
        cURIClassifier.defineFastMethod("resolve",cf.getFastMethod("resolve",IRubyObject.class));
    }

    private TernarySearchTree tst;

    public URIClassifier(Ruby runtime, RubyClass clazz) {
        super(runtime,clazz);
        tst = new TernarySearchTree(TRIE_INCREASE);
    }

    public IRubyObject initialize() {
        setInstanceVariable("@handler_map",RubyHash.newHash(getRuntime()));
        return this;
    }

    public IRubyObject register(IRubyObject uri, IRubyObject handler) {
        Object[] ptr = new Object[]{null};
        int rc = 0;
        rc = tst.insert(uri.toString(),handler,0,ptr);
        if(rc == TernarySearchTree.TST_DUPLICATE_KEY) {
            throw getRuntime().newStandardError("Handler already registered with that name");
        } else if(rc == TernarySearchTree.TST_ERROR) {
            throw getRuntime().newStandardError("Memory error registering handler");
        } else if(rc == TernarySearchTree.TST_NULL_KEY) {
            throw getRuntime().newStandardError("URI was empty");
        }
        ((RubyHash)getInstanceVariable("@handler_map")).aset(uri,handler);
        return getRuntime().getNil();
    }

    public IRubyObject unregister(IRubyObject uri) {
        IRubyObject handler = (IRubyObject)tst.delete(uri.toString());
        if(null != handler) {
            ((RubyHash)getInstanceVariable("@handler_map")).delete(uri,Block.NULL_BLOCK);
            return handler;
        }
        return getRuntime().getNil();
    }

    public IRubyObject resolve(IRubyObject _ri) {
        IRubyObject handler = null;
        int[] pref_len = new int[]{0};
        RubyArray result;
        String uri_str;
        RubyString uri = _ri.convertToString();

        uri_str = uri.toString();
        handler = (IRubyObject)tst.search(uri_str,pref_len);
        
        result = getRuntime().newArray();
        
        if(handler != null) {
            result.append(uri.substr(0, pref_len[0]));
            if(pref_len[0] == 1 && uri_str.startsWith("/")) {
                result.append(uri);
            } else {
                result.append(uri.substr(pref_len[0],uri.getByteList().length()));
            }
            result.append(handler);
        } else {
            result.append(getRuntime().getNil());
            result.append(getRuntime().getNil());
            result.append(getRuntime().getNil());
        }
        return result;
    }
}// URIClassifier
