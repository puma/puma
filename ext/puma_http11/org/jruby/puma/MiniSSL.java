package org.jruby.puma;

import org.jruby.Ruby;
import org.jruby.RubyClass;
import org.jruby.RubyHash;
import org.jruby.RubyModule;
import org.jruby.RubyNumeric;
import org.jruby.RubyObject;
import org.jruby.RubyString;

import org.jruby.anno.JRubyMethod;

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

    ks.load(new FileInputStream(key.convertToString().asJavaString()), null);
    ts.load(new FileInputStream(cert.convertToString().asJavaString()), null);

    KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
    kmf.init(ks, null);

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
    dummy = ByteBuffer.allocate(0);
    
    return this;
  }

  @JRubyMethod
  public IRubyObject inject(IRubyObject arg) {
    peerNetData.put(arg.convertToString().getBytes());
    return this;
  }

  @JRubyMethod
  public IRubyObject read() throws javax.net.ssl.SSLException {
    peerAppData.clear();
    peerNetData.flip();
    SSLEngineResult res;

    do {
      res = engine.unwrap(peerNetData, peerAppData);
    } while(res.getStatus() == SSLEngineResult.Status.OK &&
        res.getHandshakeStatus() == SSLEngineResult.HandshakeStatus.NEED_UNWRAP &&
        res.bytesProduced() == 0);

    if(peerAppData.position() == 0 && 
        res.getStatus() == SSLEngineResult.Status.OK &&
        peerNetData.hasRemaining()) {
      res = engine.unwrap(peerNetData, peerAppData);
    }

    peerNetData.compact();
    peerAppData.flip();

    byte[] bss = new byte[peerAppData.limit()];

    peerAppData.get(bss);

    RubyString str = getRuntime().newString("");
    str.setValue(new ByteList(bss));

    return str;
  }

  @JRubyMethod
  public IRubyObject write(IRubyObject arg) throws javax.net.ssl.SSLException {
    byte[] bls = arg.convertToString().getBytes();
    ByteBuffer src = ByteBuffer.wrap(bls);

    SSLEngineResult res = engine.wrap(src, netData);

    return getRuntime().newFixnum(res.bytesConsumed());
  }

  @JRubyMethod
  public IRubyObject extract() {
    netData.flip();

    byte[] bss = new byte[netData.limit()];

    netData.get(bss);
    netData.clear();

    RubyString str = getRuntime().newString("");
    str.setValue(new ByteList(bss));

    return str;
  }
}
