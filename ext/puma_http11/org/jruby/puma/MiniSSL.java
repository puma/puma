package org.jruby.puma;

import org.jruby.Ruby;
import org.jruby.RubyClass;
import org.jruby.RubyHash;
import org.jruby.RubyModule;
import org.jruby.RubyNumeric;
import org.jruby.RubyObject;
import org.jruby.RubyString;

import org.jruby.anno.JRubyMethod;

import org.jruby.runtime.Block;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;

import org.jruby.exceptions.RaiseException;

import org.jruby.util.ByteList;


import javax.net.ssl.*;
import javax.net.ssl.SSLEngineResult.*;
import java.io.*;
import java.security.*;
import java.nio.*;

public class MiniSSL extends RubyObject {
  private static ObjectAllocator ALLOCATOR = new ObjectAllocator() {
    public IRubyObject allocate(Ruby runtime, RubyClass klass) {
      return new MiniSSL(runtime, klass);
    }
  };

  public static void createMiniSSL(Ruby runtime) {
    RubyModule mPuma = runtime.defineModule("Puma");
    RubyModule ssl =   mPuma.defineModuleUnder("MiniSSL");

    mPuma.defineClassUnder("SSLError",
                           runtime.getClass("IOError"),
                           runtime.getClass("IOError").getAllocator());

    RubyClass eng = ssl.defineClassUnder("Engine",runtime.getObject(),ALLOCATOR);
    eng.defineAnnotatedMethods(MiniSSL.class);
  }

  private Ruby runtime;
  private SSLContext sslc;

  private SSLEngine  engine;

  private ByteBuffer peerAppData;
  private ByteBuffer peerNetData;
  private ByteBuffer netData;
  private ByteBuffer dummy;
  
  public MiniSSL(Ruby runtime, RubyClass klass) {
    super(runtime, klass);

    this.runtime = runtime;
  }

  @JRubyMethod(meta = true)
  public static IRubyObject server(ThreadContext context, IRubyObject recv, IRubyObject key, IRubyObject cert) {
      RubyClass klass = (RubyClass) recv;
      IRubyObject newInstance = klass.newInstance(context,
          new IRubyObject[] { key, cert },
          Block.NULL_BLOCK);

      return newInstance;
  }

  @JRubyMethod
  public IRubyObject initialize(IRubyObject key, IRubyObject cert) 
      throws java.security.KeyStoreException,
             java.io.FileNotFoundException,
             java.io.IOException,
             java.io.FileNotFoundException,
             java.security.NoSuchAlgorithmException,
             java.security.KeyManagementException,
             java.security.cert.CertificateException,
             java.security.UnrecoverableKeyException
  {
    KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
    KeyStore ts = KeyStore.getInstance(KeyStore.getDefaultType());

    char[] pass = "blahblah".toCharArray();

    ks.load(new FileInputStream(key.convertToString().asJavaString()),
                                pass);
    ts.load(new FileInputStream(cert.convertToString().asJavaString()),
            pass);

    KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
    kmf.init(ks, pass);

    TrustManagerFactory tmf = TrustManagerFactory.getInstance("SunX509");
    tmf.init(ts);

    SSLContext sslCtx = SSLContext.getInstance("TLS");

    sslCtx.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);

    sslc = sslCtx;

    engine = sslc.createSSLEngine();
    engine.setUseClientMode(false);
    // engine.setNeedClientAuth(true);

    SSLSession session = engine.getSession();
    peerNetData = ByteBuffer.allocate(session.getPacketBufferSize());
    peerAppData = ByteBuffer.allocate(session.getApplicationBufferSize());		
    netData = ByteBuffer.allocate(session.getPacketBufferSize());
    peerNetData.limit(0);
    peerAppData.limit(0);
    netData.limit(0);

    peerNetData.clear();
    peerAppData.clear();
    netData.clear();

    dummy = ByteBuffer.allocate(0);
    
    return this;
  }

  @JRubyMethod
  public IRubyObject inject(IRubyObject arg) {
    byte[] bytes = arg.convertToString().getBytes();

    peerNetData.limit(peerNetData.limit() + bytes.length);

    log("capacity: " + peerNetData.capacity() + " limit: " + peerNetData.limit());

    peerNetData.put(bytes);

    log("netData: " + peerNetData.position() + "/" + peerAppData.limit());
    return this;
  }

  @JRubyMethod
  public IRubyObject read() throws javax.net.ssl.SSLException, Exception {
    peerAppData.clear();
    peerNetData.flip();
    SSLEngineResult res;

    log("available read: " + peerNetData.position() + "/ " + peerNetData.limit());

    if(!peerNetData.hasRemaining()) {
      return getRuntime().getNil();
    }

    do {
      res = engine.unwrap(peerNetData, peerAppData);
    } while(res.getStatus() == SSLEngineResult.Status.OK &&
        res.getHandshakeStatus() == SSLEngineResult.HandshakeStatus.NEED_UNWRAP &&
        res.bytesProduced() == 0);

    log("read: ", res);

    if(peerNetData.hasRemaining()) {
      log("STILL HAD peerNetData!");
    }

    peerNetData.position(0);
    peerNetData.limit(0);

    HandshakeStatus hsStatus = runDelegatedTasks(res, engine);

    if(res.getStatus() == SSLEngineResult.Status.BUFFER_UNDERFLOW) {
      return getRuntime().getNil();
    }

    if(hsStatus == HandshakeStatus.NEED_WRAP) {
      netData.clear();
      log("netData: " + netData.limit());
      engine.wrap(dummy, netData);
      return getRuntime().getNil();
    }

    if(hsStatus == HandshakeStatus.NEED_UNWRAP) {
      return getRuntime().getNil();

      // log("peerNet: " + peerNetData.position() + "/" + peerNetData.limit());
      // log("peerApp: " + peerAppData.position() + "/" + peerAppData.limit());

      // peerNetData.compact();

      // log("peerNet: " + peerNetData.position() + "/" + peerNetData.limit());
        // do {
          // res = engine.unwrap(peerNetData, peerAppData);
        // } while(res.getStatus() == SSLEngineResult.Status.OK &&
            // res.getHandshakeStatus() == SSLEngineResult.HandshakeStatus.NEED_UNWRAP &&
            // res.bytesProduced() == 0);
      // return getRuntime().getNil();
    }

    // if(peerAppData.position() == 0 && 
        // res.getStatus() == SSLEngineResult.Status.OK &&
        // peerNetData.hasRemaining()) {
      // res = engine.unwrap(peerNetData, peerAppData);
    // }

    byte[] bss = new byte[peerAppData.limit()];

    peerAppData.get(bss);

    RubyString str = getRuntime().newString("");
    str.setValue(new ByteList(bss));

    return str;
  }

  private static HandshakeStatus runDelegatedTasks(SSLEngineResult result,
      SSLEngine engine) throws Exception {

    HandshakeStatus hsStatus = result.getHandshakeStatus();

    if(hsStatus == HandshakeStatus.NEED_TASK) {
      Runnable runnable;
      while ((runnable = engine.getDelegatedTask()) != null) {
        log("\trunning delegated task...");
        runnable.run();
      }
      hsStatus = engine.getHandshakeStatus();
      if (hsStatus == HandshakeStatus.NEED_TASK) {
        throw new Exception(
            "handshake shouldn't need additional tasks");
      }
      log("\tnew HandshakeStatus: " + hsStatus);
    }

    return hsStatus;
  }
  

  private static void log(String str, SSLEngineResult result) {
    System.out.println("The format of the SSLEngineResult is: \n" +
        "\t\"getStatus() / getHandshakeStatus()\" +\n" +
        "\t\"bytesConsumed() / bytesProduced()\"\n");

    HandshakeStatus hsStatus = result.getHandshakeStatus();
    log(str +
        result.getStatus() + "/" + hsStatus + ", " +
        result.bytesConsumed() + "/" + result.bytesProduced() +
        " bytes");
    if (hsStatus == HandshakeStatus.FINISHED) {
      log("\t...ready for application data");
    }
  }

  private static void log(String str) {
    System.out.println(str);
  }
  
  

  @JRubyMethod
  public IRubyObject write(IRubyObject arg) throws javax.net.ssl.SSLException {
    log("write from: " + netData.position());

    byte[] bls = arg.convertToString().getBytes();
    ByteBuffer src = ByteBuffer.wrap(bls);

    SSLEngineResult res = engine.wrap(src, netData);

    return getRuntime().newFixnum(res.bytesConsumed());
  }

  @JRubyMethod
  public IRubyObject extract() {
    netData.flip();

    if(!netData.hasRemaining()) {
      return getRuntime().getNil();
    }

    byte[] bss = new byte[netData.limit()];

    netData.get(bss);
    netData.clear();

    RubyString str = getRuntime().newString("");
    str.setValue(new ByteList(bss));

    return str;
  }
}
