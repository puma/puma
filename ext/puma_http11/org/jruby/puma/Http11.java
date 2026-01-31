package org.jruby.puma;

import org.jruby.Ruby;
import org.jruby.RubyClass;
import org.jruby.RubyHash;
import org.jruby.RubyModule;
import org.jruby.RubyNumeric;
import org.jruby.RubyObject;
import org.jruby.RubyString;

import org.jruby.anno.JRubyMethod;

import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;

import org.jruby.exceptions.RaiseException;

import org.jruby.util.ByteList;

import java.util.Arrays;

import static java.util.Arrays.stream;

/**
 * @author <a href="mailto:ola.bini@ki.se">Ola Bini</a>
 * @author <a href="mailto:headius@headius.com">Charles Oliver Nutter</a>
 */
public class Http11 extends RubyObject {

    public static String getEnvOrProperty(String name) {
        String envValue = System.getenv(name);
        return (envValue != null) ? envValue : System.getProperty(name);
    }

    public static int getConstLength(String name, Integer defaultValue) {
        String stringValue = getEnvOrProperty(name);
        if (stringValue == null || stringValue.isEmpty()) return defaultValue;

        try {
            int value = Integer.parseUnsignedInt(stringValue);
            if (value <= 0) {
                throw new NumberFormatException("The number is not positive.");
            }
            return value;
        } catch (NumberFormatException e) {
            System.err.println(String.format("The value %s for %s is invalid. Using default value %d instead.", stringValue, name, defaultValue));
            return defaultValue;
        }
    }

    public static void createHttp11(Ruby runtime) {
        RubyModule mPuma = runtime.defineModule("Puma");
        mPuma.defineClassUnder("HttpParserError",runtime.getClass("StandardError"),runtime.getClass("StandardError").getAllocator());

        // Set up pre-allocated strings for HTTP/1.1 headers and CGI variables
        RubyString[] envStrings =
                stream(EnvKey.values())
                        .map((key) -> internRubyString(runtime, key))
                        .toArray(RubyString[]::new);

        RubyClass cHttpParser = mPuma.defineClassUnder("HttpParser",runtime.getObject(),(r, c) -> new Http11(r, c, envStrings));
        cHttpParser.defineAnnotatedMethods(Http11.class);
    }

    private static RubyString internRubyString(Ruby runtime, EnvKey key) {
        return runtime.freezeAndDedupString(RubyString.newStringShared(runtime, key.httpName));
    }

    private final Ruby runtime;
    private final Http11Parser hp;
    final RubyString[] envStrings;
    private RubyString body;

    public Http11(Ruby runtime, RubyClass clazz, RubyString[] envStrings) {
        super(runtime,clazz);
        this.runtime = runtime;
        this.hp = new Http11Parser();
        this.envStrings = envStrings;
        this.hp.init();
    }

    public static void validateMaxLength(Ruby runtime, int len, int max, String msg) {
        if(len>max) {
            throw newHTTPParserError(runtime, msg);
        }
    }

    private static RaiseException newHTTPParserError(Ruby runtime, String msg) {
        return runtime.newRaiseException(getHTTPParserError(runtime), msg);
    }

    private static RubyClass getHTTPParserError(Ruby runtime) {
        // Cheaper to look this up lazily than cache eagerly and consume a field, since it's rarely encountered
        return (RubyClass)runtime.getModule("Puma").getConstant("HttpParserError");
    }

    private static RubyString fstringForField(RubyString[] envStrings, byte[] buffer, int field, int flen) {
        EnvKey key = EnvKey.keyForField(buffer, field, flen);
        if (key != null) return envStrings[key.ordinal()];
        return null;
    }

    private static boolean is_ows(int c) {
        return c == ' ' || c == '\t';
    }

    public static final byte[] HTTP_PREFIX_BYTELIST = ByteList.plain("HTTP_");
    private static final int HTTP_PREFIX_LENGTH = 5;
    public static final byte[] COMMA_SPACE_BYTELIST = ByteList.plain(", ");

    public static void http_field(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int vlen) {
        RubyString f;
        IRubyObject v;
        int field_len = hp.field_len;
        validateFieldNameLength(runtime, field_len);
        validateFieldValueLength(runtime, vlen);

        byte[] buffer = hp.buffer;
        int field_start = hp.field_start;
        f = fstringForField(envStrings, buffer, field_start, field_len);

        if (f == null) {
            f = newHttpHeader(runtime, buffer, field_start, field_len);
        }

        int mark = hp.mark;
        while (vlen > 0) {
            if (!is_ows(buffer[mark + vlen - 1])) break;
            vlen--;
        }
        while (vlen > 0 && is_ows(buffer[mark])) {
            vlen--;
            mark++;
        }

        RubyHash req = hp.data;
        v = req.fastARef(f);
        if (v == null || v.isNil()) {
            req.fastASet(f, RubyString.newStringShared(runtime, buffer, mark, vlen));
        } else {
            RubyString vs = v.convertToString();
            vs.cat(COMMA_SPACE_BYTELIST);
            vs.cat(buffer, mark, vlen);
        }
    }

    private static RubyString newHttpHeader(Ruby runtime, byte[] buffer, int field_start, int field_len) {
        byte[] bytes = new byte[HTTP_PREFIX_LENGTH + field_len];
        System.arraycopy(HTTP_PREFIX_BYTELIST, 0, bytes, 0, HTTP_PREFIX_LENGTH);
        snakeCaseCopy(buffer, field_start, field_len, bytes, HTTP_PREFIX_LENGTH);
        return RubyString.newStringNoCopy(runtime, bytes);
    }

    static void snakeCaseCopy(byte[] s, int soff, int slen, byte[] d, int doff) {
        for (int i = 0; i < slen; i++) {
            int si = soff + i;
            byte sch = s[si];
            int di = doff + i;
            byte dch = snakeUpcase(sch);
            d[di] = dch;
        }
    }

    static byte snakeUpcase(byte ch) {
        if (ch >= 'a' && ch <= 'z')
            ch = (byte) (ch & ~0x20);
        else if (ch == '_')
            ch = ',';
        else if (ch == '-')
            ch = '_';
        return ch;
    }

    public static void request_method(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        hp.data.fastASet(envStrings[EnvKey.REQUEST_METHOD.ordinal()], newValueString(runtime, hp, length));
    }

    public static void request_uri(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        validateRequestURILength(runtime, length);
        hp.data.fastASet(envStrings[EnvKey.REQUEST_URI.ordinal()], newValueString(runtime, hp, length));
    }

    public static void fragment(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        validateFragmentLength(runtime, length);
        hp.data.fastASet(envStrings[EnvKey.FRAGMENT.ordinal()], newValueString(runtime, hp, length));
    }

    public static void request_path(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        validateRequestPathLength(runtime, length);
        hp.data.fastASet(envStrings[EnvKey.REQUEST_PATH.ordinal()], newValueString(runtime, hp, length));
    }

    public static void query_string(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        validateQueryStringLength(runtime, length);
        hp.data.fastASet(envStrings[EnvKey.QUERY_STRING.ordinal()], newQueryString(runtime, hp, length));
    }

    public static void server_protocol(Ruby runtime, RubyString[] envStrings, Http11Parser hp, int length) {
        hp.data.fastASet(envStrings[EnvKey.SERVER_PROTOCOL.ordinal()], newValueString(runtime, hp, length));
    }

    public void header_done(Ruby runtime, Http11Parser hp, int at, int length) {
        body = RubyString.newStringShared(runtime, hp.buffer, at, length);
    }

    @JRubyMethod
    public IRubyObject initialize() {
        this.hp.init();
        return this;
    }

    @JRubyMethod
    public IRubyObject reset(ThreadContext context) {
        this.hp.init();
        return context.nil;
    }

    @JRubyMethod
    public IRubyObject finish(ThreadContext context) {
        Http11Parser hp = this.hp;
        hp.finish();
        return hp.is_finished() ? context.tru : context.fals;
    }

    @JRubyMethod
    public IRubyObject execute(IRubyObject req_hash, IRubyObject data, IRubyObject start) {
        Ruby runtime = this.runtime;
        int from = RubyNumeric.fix2int(start);
        RubyString dataString = (RubyString) data;
        dataString.setByteListShared();
        ByteList d = dataString.getByteList();
        if(from >= d.length()) {
            throw newHTTPParserError(runtime, "Requested start is after data buffer end.");
        } else {
            Http11Parser hp = this.hp;

            hp.data = (RubyHash) req_hash;

            hp.execute(runtime, this, d,from);

            validateMaxHeaderLength(runtime, hp);

            if(hp.has_error()) {
                throw newHTTPParserError(runtime, "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?");
            } else {
                return runtime.newFixnum(hp.nread);
            }
        }
    }

    @JRubyMethod(name = "error?")
    public IRubyObject has_error(ThreadContext context) {
        return this.hp.has_error() ? context.tru : context.fals;
    }

    @JRubyMethod(name = "finished?")
    public IRubyObject is_finished(ThreadContext context) {
        return this.hp.is_finished() ? context.tru : context.fals;
    }

    @JRubyMethod
    public IRubyObject nread() {
        return runtime.newFixnum(this.hp.nread);
    }

    @JRubyMethod
    public IRubyObject body() {
        return body;
    }

    public final static int MAX_FIELD_NAME_LENGTH = 256;
    public final static String MAX_FIELD_NAME_LENGTH_ERR = "HTTP element FIELD_NAME is longer than the 256 allowed length.";
    public final static int MAX_FIELD_VALUE_LENGTH = 80 * 1024;
    public final static String MAX_FIELD_VALUE_LENGTH_ERR = "HTTP element FIELD_VALUE is longer than the 81920 allowed length.";
    public final static int MAX_REQUEST_URI_LENGTH = getConstLength("PUMA_REQUEST_URI_MAX_LENGTH", 1024 * 12);
    public final static String MAX_REQUEST_URI_LENGTH_ERR = "HTTP element REQUEST_URI is longer than the " + MAX_REQUEST_URI_LENGTH + " allowed length.";
    public final static int MAX_FRAGMENT_LENGTH = 1024;
    public final static String MAX_FRAGMENT_LENGTH_ERR = "HTTP element FRAGMENT is longer than the 1024 allowed length.";
    public final static int MAX_REQUEST_PATH_LENGTH = getConstLength("PUMA_REQUEST_PATH_MAX_LENGTH", 8192);
    public final static String MAX_REQUEST_PATH_LENGTH_ERR = "HTTP element REQUEST_PATH is longer than the " + MAX_REQUEST_PATH_LENGTH + " allowed length.";
    public final static int MAX_QUERY_STRING_LENGTH = getConstLength("PUMA_QUERY_STRING_MAX_LENGTH", 10 * 1024);
    public final static String MAX_QUERY_STRING_LENGTH_ERR = "HTTP element QUERY_STRING is longer than the " + MAX_QUERY_STRING_LENGTH +" allowed length.";
    public final static int MAX_HEADER_LENGTH = 1024 * (80 + 32);
    public final static String MAX_HEADER_LENGTH_ERR = "HTTP element HEADER is longer than the 114688 allowed length.";

    private static void validateFieldNameLength(Ruby runtime, int field_len) {
        validateMaxLength(runtime, field_len, MAX_FIELD_NAME_LENGTH, MAX_FIELD_NAME_LENGTH_ERR);
    }

    private static void validateFieldValueLength(Ruby runtime, int field_len) {
        validateMaxLength(runtime, field_len, MAX_FIELD_VALUE_LENGTH, MAX_FIELD_VALUE_LENGTH_ERR);
    }

    private static void validateRequestURILength(Ruby runtime, int length) {
        validateMaxLength(runtime, length, MAX_REQUEST_URI_LENGTH, MAX_REQUEST_URI_LENGTH_ERR);
    }

    private static void validateFragmentLength(Ruby runtime, int length) {
        validateMaxLength(runtime, length, MAX_FRAGMENT_LENGTH, MAX_FRAGMENT_LENGTH_ERR);
    }

    private static void validateRequestPathLength(Ruby runtime, int length) {
        validateMaxLength(runtime, length, MAX_REQUEST_PATH_LENGTH, MAX_REQUEST_PATH_LENGTH_ERR);
    }

    private static void validateQueryStringLength(Ruby runtime, int length) {
        validateMaxLength(runtime, length, MAX_QUERY_STRING_LENGTH, MAX_QUERY_STRING_LENGTH_ERR);
    }

    private static RubyString newValueString(Ruby runtime, Http11Parser hp, int length) {
        return RubyString.newStringShared(runtime, hp.buffer, hp.mark, length);
    }

    private static RubyString newQueryString(Ruby runtime, Http11Parser hp, int length) {
        return RubyString.newStringShared(runtime, hp.buffer, hp.query_start, length);
    }

    private static void validateMaxHeaderLength(Ruby runtime, Http11Parser hp) {
        validateMaxLength(runtime, hp.nread, MAX_HEADER_LENGTH, MAX_HEADER_LENGTH_ERR);
    }
}// Http11
