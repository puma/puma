// line 1 "org/jruby/mongrel/http11_parser.rl"
package org.jruby.mongrel;

import org.jruby.util.ByteList;

public class Http11Parser {

/** machine **/
// line 104 "org/jruby/mongrel/http11_parser.rl"


/** Data **/

// line 15 "org/jruby/mongrel/Http11Parser.java"
private static void init__http_parser_actions_0( byte[] r )
{
	r[0]=0; r[1]=1; r[2]=0; r[3]=1; r[4]=1; r[5]=1; r[6]=2; r[7]=1; 
	r[8]=3; r[9]=1; r[10]=4; r[11]=1; r[12]=5; r[13]=1; r[14]=6; r[15]=1; 
	r[16]=7; r[17]=1; r[18]=9; r[19]=1; r[20]=10; r[21]=1; r[22]=11; r[23]=2; 
	r[24]=8; r[25]=6; r[26]=2; r[27]=10; r[28]=6; r[29]=3; r[30]=7; r[31]=8; 
	r[32]=6; 
}

private static byte[] create__http_parser_actions( )
{
	byte[] r = new byte[33];
	init__http_parser_actions_0( r );
	return r;
}

private static final byte _http_parser_actions[] = create__http_parser_actions();


private static void init__http_parser_key_offsets_0( short[] r )
{
	r[0]=0; r[1]=0; r[2]=8; r[3]=17; r[4]=27; r[5]=28; r[6]=29; r[7]=30; 
	r[8]=31; r[9]=32; r[10]=33; r[11]=35; r[12]=38; r[13]=40; r[14]=43; r[15]=44; 
	r[16]=60; r[17]=61; r[18]=77; r[19]=79; r[20]=80; r[21]=90; r[22]=99; r[23]=105; 
	r[24]=111; r[25]=122; r[26]=128; r[27]=134; r[28]=144; r[29]=150; r[30]=156; r[31]=165; 
	r[32]=174; r[33]=180; r[34]=186; r[35]=195; r[36]=204; r[37]=213; r[38]=222; r[39]=231; 
	r[40]=240; r[41]=249; r[42]=258; r[43]=267; r[44]=276; r[45]=285; r[46]=294; r[47]=303; 
	r[48]=312; r[49]=321; r[50]=330; r[51]=339; r[52]=348; r[53]=349; 
}

private static short[] create__http_parser_key_offsets( )
{
	short[] r = new short[54];
	init__http_parser_key_offsets_0( r );
	return r;
}

private static final short _http_parser_key_offsets[] = create__http_parser_key_offsets();


private static void init__http_parser_trans_keys_0( char[] r )
{
	r[0]=36; r[1]=95; r[2]=45; r[3]=46; r[4]=48; r[5]=57; r[6]=65; r[7]=90; 
	r[8]=32; r[9]=36; r[10]=95; r[11]=45; r[12]=46; r[13]=48; r[14]=57; r[15]=65; 
	r[16]=90; r[17]=42; r[18]=43; r[19]=47; r[20]=58; r[21]=45; r[22]=57; r[23]=65; 
	r[24]=90; r[25]=97; r[26]=122; r[27]=32; r[28]=72; r[29]=84; r[30]=84; r[31]=80; 
	r[32]=47; r[33]=48; r[34]=57; r[35]=46; r[36]=48; r[37]=57; r[38]=48; r[39]=57; 
	r[40]=13; r[41]=48; r[42]=57; r[43]=10; r[44]=13; r[45]=33; r[46]=124; r[47]=126; 
	r[48]=35; r[49]=39; r[50]=42; r[51]=43; r[52]=45; r[53]=46; r[54]=48; r[55]=57; 
	r[56]=65; r[57]=90; r[58]=94; r[59]=122; r[60]=10; r[61]=33; r[62]=58; r[63]=124; 
	r[64]=126; r[65]=35; r[66]=39; r[67]=42; r[68]=43; r[69]=45; r[70]=46; r[71]=48; 
	r[72]=57; r[73]=65; r[74]=90; r[75]=94; r[76]=122; r[77]=13; r[78]=32; r[79]=13; 
	r[80]=43; r[81]=58; r[82]=45; r[83]=46; r[84]=48; r[85]=57; r[86]=65; r[87]=90; 
	r[88]=97; r[89]=122; r[90]=32; r[91]=37; r[92]=60; r[93]=62; r[94]=127; r[95]=0; 
	r[96]=31; r[97]=34; r[98]=35; r[99]=48; r[100]=57; r[101]=65; r[102]=70; r[103]=97; 
	r[104]=102; r[105]=48; r[106]=57; r[107]=65; r[108]=70; r[109]=97; r[110]=102; r[111]=32; 
	r[112]=37; r[113]=59; r[114]=60; r[115]=62; r[116]=63; r[117]=127; r[118]=0; r[119]=31; 
	r[120]=34; r[121]=35; r[122]=48; r[123]=57; r[124]=65; r[125]=70; r[126]=97; r[127]=102; 
	r[128]=48; r[129]=57; r[130]=65; r[131]=70; r[132]=97; r[133]=102; r[134]=32; r[135]=37; 
	r[136]=60; r[137]=62; r[138]=63; r[139]=127; r[140]=0; r[141]=31; r[142]=34; r[143]=35; 
	r[144]=48; r[145]=57; r[146]=65; r[147]=70; r[148]=97; r[149]=102; r[150]=48; r[151]=57; 
	r[152]=65; r[153]=70; r[154]=97; r[155]=102; r[156]=32; r[157]=37; r[158]=60; r[159]=62; 
	r[160]=127; r[161]=0; r[162]=31; r[163]=34; r[164]=35; r[165]=32; r[166]=37; r[167]=60; 
	r[168]=62; r[169]=127; r[170]=0; r[171]=31; r[172]=34; r[173]=35; r[174]=48; r[175]=57; 
	r[176]=65; r[177]=70; r[178]=97; r[179]=102; r[180]=48; r[181]=57; r[182]=65; r[183]=70; 
	r[184]=97; r[185]=102; r[186]=32; r[187]=36; r[188]=95; r[189]=45; r[190]=46; r[191]=48; 
	r[192]=57; r[193]=65; r[194]=90; r[195]=32; r[196]=36; r[197]=95; r[198]=45; r[199]=46; 
	r[200]=48; r[201]=57; r[202]=65; r[203]=90; r[204]=32; r[205]=36; r[206]=95; r[207]=45; 
	r[208]=46; r[209]=48; r[210]=57; r[211]=65; r[212]=90; r[213]=32; r[214]=36; r[215]=95; 
	r[216]=45; r[217]=46; r[218]=48; r[219]=57; r[220]=65; r[221]=90; r[222]=32; r[223]=36; 
	r[224]=95; r[225]=45; r[226]=46; r[227]=48; r[228]=57; r[229]=65; r[230]=90; r[231]=32; 
	r[232]=36; r[233]=95; r[234]=45; r[235]=46; r[236]=48; r[237]=57; r[238]=65; r[239]=90; 
	r[240]=32; r[241]=36; r[242]=95; r[243]=45; r[244]=46; r[245]=48; r[246]=57; r[247]=65; 
	r[248]=90; r[249]=32; r[250]=36; r[251]=95; r[252]=45; r[253]=46; r[254]=48; r[255]=57; 
	r[256]=65; r[257]=90; r[258]=32; r[259]=36; r[260]=95; r[261]=45; r[262]=46; r[263]=48; 
	r[264]=57; r[265]=65; r[266]=90; r[267]=32; r[268]=36; r[269]=95; r[270]=45; r[271]=46; 
	r[272]=48; r[273]=57; r[274]=65; r[275]=90; r[276]=32; r[277]=36; r[278]=95; r[279]=45; 
	r[280]=46; r[281]=48; r[282]=57; r[283]=65; r[284]=90; r[285]=32; r[286]=36; r[287]=95; 
	r[288]=45; r[289]=46; r[290]=48; r[291]=57; r[292]=65; r[293]=90; r[294]=32; r[295]=36; 
	r[296]=95; r[297]=45; r[298]=46; r[299]=48; r[300]=57; r[301]=65; r[302]=90; r[303]=32; 
	r[304]=36; r[305]=95; r[306]=45; r[307]=46; r[308]=48; r[309]=57; r[310]=65; r[311]=90; 
	r[312]=32; r[313]=36; r[314]=95; r[315]=45; r[316]=46; r[317]=48; r[318]=57; r[319]=65; 
	r[320]=90; r[321]=32; r[322]=36; r[323]=95; r[324]=45; r[325]=46; r[326]=48; r[327]=57; 
	r[328]=65; r[329]=90; r[330]=32; r[331]=36; r[332]=95; r[333]=45; r[334]=46; r[335]=48; 
	r[336]=57; r[337]=65; r[338]=90; r[339]=32; r[340]=36; r[341]=95; r[342]=45; r[343]=46; 
	r[344]=48; r[345]=57; r[346]=65; r[347]=90; r[348]=32; r[349]=0; 
}

private static char[] create__http_parser_trans_keys( )
{
	char[] r = new char[350];
	init__http_parser_trans_keys_0( r );
	return r;
}

private static final char _http_parser_trans_keys[] = create__http_parser_trans_keys();


private static void init__http_parser_single_lengths_0( byte[] r )
{
	r[0]=0; r[1]=2; r[2]=3; r[3]=4; r[4]=1; r[5]=1; r[6]=1; r[7]=1; 
	r[8]=1; r[9]=1; r[10]=0; r[11]=1; r[12]=0; r[13]=1; r[14]=1; r[15]=4; 
	r[16]=1; r[17]=4; r[18]=2; r[19]=1; r[20]=2; r[21]=5; r[22]=0; r[23]=0; 
	r[24]=7; r[25]=0; r[26]=0; r[27]=6; r[28]=0; r[29]=0; r[30]=5; r[31]=5; 
	r[32]=0; r[33]=0; r[34]=3; r[35]=3; r[36]=3; r[37]=3; r[38]=3; r[39]=3; 
	r[40]=3; r[41]=3; r[42]=3; r[43]=3; r[44]=3; r[45]=3; r[46]=3; r[47]=3; 
	r[48]=3; r[49]=3; r[50]=3; r[51]=3; r[52]=1; r[53]=0; 
}

private static byte[] create__http_parser_single_lengths( )
{
	byte[] r = new byte[54];
	init__http_parser_single_lengths_0( r );
	return r;
}

private static final byte _http_parser_single_lengths[] = create__http_parser_single_lengths();


private static void init__http_parser_range_lengths_0( byte[] r )
{
	r[0]=0; r[1]=3; r[2]=3; r[3]=3; r[4]=0; r[5]=0; r[6]=0; r[7]=0; 
	r[8]=0; r[9]=0; r[10]=1; r[11]=1; r[12]=1; r[13]=1; r[14]=0; r[15]=6; 
	r[16]=0; r[17]=6; r[18]=0; r[19]=0; r[20]=4; r[21]=2; r[22]=3; r[23]=3; 
	r[24]=2; r[25]=3; r[26]=3; r[27]=2; r[28]=3; r[29]=3; r[30]=2; r[31]=2; 
	r[32]=3; r[33]=3; r[34]=3; r[35]=3; r[36]=3; r[37]=3; r[38]=3; r[39]=3; 
	r[40]=3; r[41]=3; r[42]=3; r[43]=3; r[44]=3; r[45]=3; r[46]=3; r[47]=3; 
	r[48]=3; r[49]=3; r[50]=3; r[51]=3; r[52]=0; r[53]=0; 
}

private static byte[] create__http_parser_range_lengths( )
{
	byte[] r = new byte[54];
	init__http_parser_range_lengths_0( r );
	return r;
}

private static final byte _http_parser_range_lengths[] = create__http_parser_range_lengths();


private static void init__http_parser_index_offsets_0( short[] r )
{
	r[0]=0; r[1]=0; r[2]=6; r[3]=13; r[4]=21; r[5]=23; r[6]=25; r[7]=27; 
	r[8]=29; r[9]=31; r[10]=33; r[11]=35; r[12]=38; r[13]=40; r[14]=43; r[15]=45; 
	r[16]=56; r[17]=58; r[18]=69; r[19]=72; r[20]=74; r[21]=81; r[22]=89; r[23]=93; 
	r[24]=97; r[25]=107; r[26]=111; r[27]=115; r[28]=124; r[29]=128; r[30]=132; r[31]=140; 
	r[32]=148; r[33]=152; r[34]=156; r[35]=163; r[36]=170; r[37]=177; r[38]=184; r[39]=191; 
	r[40]=198; r[41]=205; r[42]=212; r[43]=219; r[44]=226; r[45]=233; r[46]=240; r[47]=247; 
	r[48]=254; r[49]=261; r[50]=268; r[51]=275; r[52]=282; r[53]=284; 
}

private static short[] create__http_parser_index_offsets( )
{
	short[] r = new short[54];
	init__http_parser_index_offsets_0( r );
	return r;
}

private static final short _http_parser_index_offsets[] = create__http_parser_index_offsets();


private static void init__http_parser_indicies_0( byte[] r )
{
	r[0]=0; r[1]=0; r[2]=0; r[3]=0; r[4]=0; r[5]=1; r[6]=2; r[7]=3; 
	r[8]=3; r[9]=3; r[10]=3; r[11]=3; r[12]=1; r[13]=4; r[14]=5; r[15]=6; 
	r[16]=7; r[17]=5; r[18]=5; r[19]=5; r[20]=1; r[21]=8; r[22]=1; r[23]=9; 
	r[24]=1; r[25]=10; r[26]=1; r[27]=11; r[28]=1; r[29]=12; r[30]=1; r[31]=13; 
	r[32]=1; r[33]=14; r[34]=1; r[35]=15; r[36]=14; r[37]=1; r[38]=16; r[39]=1; 
	r[40]=17; r[41]=16; r[42]=1; r[43]=18; r[44]=1; r[45]=19; r[46]=20; r[47]=20; 
	r[48]=20; r[49]=20; r[50]=20; r[51]=20; r[52]=20; r[53]=20; r[54]=20; r[55]=1; 
	r[56]=21; r[57]=1; r[58]=22; r[59]=23; r[60]=22; r[61]=22; r[62]=22; r[63]=22; 
	r[64]=22; r[65]=22; r[66]=22; r[67]=22; r[68]=1; r[69]=25; r[70]=26; r[71]=24; 
	r[72]=25; r[73]=27; r[74]=28; r[75]=29; r[76]=28; r[77]=28; r[78]=28; r[79]=28; 
	r[80]=1; r[81]=8; r[82]=30; r[83]=1; r[84]=1; r[85]=1; r[86]=1; r[87]=1; 
	r[88]=29; r[89]=31; r[90]=31; r[91]=31; r[92]=1; r[93]=29; r[94]=29; r[95]=29; 
	r[96]=1; r[97]=32; r[98]=34; r[99]=35; r[100]=1; r[101]=1; r[102]=36; r[103]=1; 
	r[104]=1; r[105]=1; r[106]=33; r[107]=37; r[108]=37; r[109]=37; r[110]=1; r[111]=33; 
	r[112]=33; r[113]=33; r[114]=1; r[115]=8; r[116]=39; r[117]=1; r[118]=1; r[119]=40; 
	r[120]=1; r[121]=1; r[122]=1; r[123]=38; r[124]=41; r[125]=41; r[126]=41; r[127]=1; 
	r[128]=38; r[129]=38; r[130]=38; r[131]=1; r[132]=42; r[133]=44; r[134]=1; r[135]=1; 
	r[136]=1; r[137]=1; r[138]=1; r[139]=43; r[140]=45; r[141]=47; r[142]=1; r[143]=1; 
	r[144]=1; r[145]=1; r[146]=1; r[147]=46; r[148]=48; r[149]=48; r[150]=48; r[151]=1; 
	r[152]=46; r[153]=46; r[154]=46; r[155]=1; r[156]=2; r[157]=49; r[158]=49; r[159]=49; 
	r[160]=49; r[161]=49; r[162]=1; r[163]=2; r[164]=50; r[165]=50; r[166]=50; r[167]=50; 
	r[168]=50; r[169]=1; r[170]=2; r[171]=51; r[172]=51; r[173]=51; r[174]=51; r[175]=51; 
	r[176]=1; r[177]=2; r[178]=52; r[179]=52; r[180]=52; r[181]=52; r[182]=52; r[183]=1; 
	r[184]=2; r[185]=53; r[186]=53; r[187]=53; r[188]=53; r[189]=53; r[190]=1; r[191]=2; 
	r[192]=54; r[193]=54; r[194]=54; r[195]=54; r[196]=54; r[197]=1; r[198]=2; r[199]=55; 
	r[200]=55; r[201]=55; r[202]=55; r[203]=55; r[204]=1; r[205]=2; r[206]=56; r[207]=56; 
	r[208]=56; r[209]=56; r[210]=56; r[211]=1; r[212]=2; r[213]=57; r[214]=57; r[215]=57; 
	r[216]=57; r[217]=57; r[218]=1; r[219]=2; r[220]=58; r[221]=58; r[222]=58; r[223]=58; 
	r[224]=58; r[225]=1; r[226]=2; r[227]=59; r[228]=59; r[229]=59; r[230]=59; r[231]=59; 
	r[232]=1; r[233]=2; r[234]=60; r[235]=60; r[236]=60; r[237]=60; r[238]=60; r[239]=1; 
	r[240]=2; r[241]=61; r[242]=61; r[243]=61; r[244]=61; r[245]=61; r[246]=1; r[247]=2; 
	r[248]=62; r[249]=62; r[250]=62; r[251]=62; r[252]=62; r[253]=1; r[254]=2; r[255]=63; 
	r[256]=63; r[257]=63; r[258]=63; r[259]=63; r[260]=1; r[261]=2; r[262]=64; r[263]=64; 
	r[264]=64; r[265]=64; r[266]=64; r[267]=1; r[268]=2; r[269]=65; r[270]=65; r[271]=65; 
	r[272]=65; r[273]=65; r[274]=1; r[275]=2; r[276]=66; r[277]=66; r[278]=66; r[279]=66; 
	r[280]=66; r[281]=1; r[282]=2; r[283]=1; r[284]=1; r[285]=0; 
}

private static byte[] create__http_parser_indicies( )
{
	byte[] r = new byte[286];
	init__http_parser_indicies_0( r );
	return r;
}

private static final byte _http_parser_indicies[] = create__http_parser_indicies();


private static void init__http_parser_trans_targs_wi_0( byte[] r )
{
	r[0]=2; r[1]=0; r[2]=3; r[3]=34; r[4]=4; r[5]=20; r[6]=24; r[7]=21; 
	r[8]=5; r[9]=6; r[10]=7; r[11]=8; r[12]=9; r[13]=10; r[14]=11; r[15]=12; 
	r[16]=13; r[17]=14; r[18]=15; r[19]=16; r[20]=17; r[21]=53; r[22]=17; r[23]=18; 
	r[24]=19; r[25]=14; r[26]=18; r[27]=19; r[28]=20; r[29]=21; r[30]=22; r[31]=23; 
	r[32]=5; r[33]=24; r[34]=25; r[35]=27; r[36]=30; r[37]=26; r[38]=27; r[39]=28; 
	r[40]=30; r[41]=29; r[42]=5; r[43]=31; r[44]=32; r[45]=5; r[46]=31; r[47]=32; 
	r[48]=33; r[49]=35; r[50]=36; r[51]=37; r[52]=38; r[53]=39; r[54]=40; r[55]=41; 
	r[56]=42; r[57]=43; r[58]=44; r[59]=45; r[60]=46; r[61]=47; r[62]=48; r[63]=49; 
	r[64]=50; r[65]=51; r[66]=52; 
}

private static byte[] create__http_parser_trans_targs_wi( )
{
	byte[] r = new byte[67];
	init__http_parser_trans_targs_wi_0( r );
	return r;
}

private static final byte _http_parser_trans_targs_wi[] = create__http_parser_trans_targs_wi();


private static void init__http_parser_trans_actions_wi_0( byte[] r )
{
	r[0]=1; r[1]=0; r[2]=11; r[3]=0; r[4]=1; r[5]=1; r[6]=1; r[7]=1; 
	r[8]=13; r[9]=1; r[10]=0; r[11]=0; r[12]=0; r[13]=0; r[14]=0; r[15]=0; 
	r[16]=0; r[17]=17; r[18]=0; r[19]=0; r[20]=3; r[21]=21; r[22]=0; r[23]=5; 
	r[24]=7; r[25]=9; r[26]=7; r[27]=0; r[28]=0; r[29]=0; r[30]=0; r[31]=0; 
	r[32]=26; r[33]=0; r[34]=0; r[35]=19; r[36]=19; r[37]=0; r[38]=0; r[39]=0; 
	r[40]=0; r[41]=0; r[42]=29; r[43]=15; r[44]=15; r[45]=23; r[46]=0; r[47]=0; 
	r[48]=0; r[49]=0; r[50]=0; r[51]=0; r[52]=0; r[53]=0; r[54]=0; r[55]=0; 
	r[56]=0; r[57]=0; r[58]=0; r[59]=0; r[60]=0; r[61]=0; r[62]=0; r[63]=0; 
	r[64]=0; r[65]=0; r[66]=0; 
}

private static byte[] create__http_parser_trans_actions_wi( )
{
	byte[] r = new byte[67];
	init__http_parser_trans_actions_wi_0( r );
	return r;
}

private static final byte _http_parser_trans_actions_wi[] = create__http_parser_trans_actions_wi();


static final int http_parser_start = 1;
static final int http_parser_first_final = 53;
static final int http_parser_error = 0;

static final int http_parser_en_main = 1;

// line 108 "org/jruby/mongrel/http11_parser.rl"

   public static interface ElementCB {
     public void call(Object data, int at, int length);
   }

   public static interface FieldCB {
     public void call(Object data, int field, int flen, int value, int vlen);
   }

   public static class HttpParser {
      int cs;
      int body_start;
      int content_len;
      int nread;
      int mark;
      int field_start;
      int field_len;
      int query_start;

      Object data;
      ByteList buffer;

      public FieldCB http_field;
      public ElementCB request_method;
      public ElementCB request_uri;
      public ElementCB request_path;
      public ElementCB query_string;
      public ElementCB http_version;
      public ElementCB header_done;

      public void init() {
          cs = 0;

          
// line 314 "org/jruby/mongrel/Http11Parser.java"
	{
	cs = http_parser_start;
	}
// line 142 "org/jruby/mongrel/http11_parser.rl"

          body_start = 0;
          content_len = 0;
          mark = 0;
          nread = 0;
          field_len = 0;
          field_start = 0;
      }
   }

   public final HttpParser parser = new HttpParser();

   public int execute(ByteList buffer, int off) {
     int p, pe;
     int cs = parser.cs;
     int len = buffer.realSize;
     assert off<=len : "offset past end of buffer";

     p = off;
     pe = len;
     byte[] data = buffer.bytes;
     parser.buffer = buffer;

     
// line 343 "org/jruby/mongrel/Http11Parser.java"
	{
	int _klen;
	int _trans;
	int _acts;
	int _nacts;
	int _keys;

	if ( p != pe ) {
	if ( cs != 0 ) {
	_resume: while ( true ) {
	_again: do {
	_match: do {
	_keys = _http_parser_key_offsets[cs];
	_trans = _http_parser_index_offsets[cs];
	_klen = _http_parser_single_lengths[cs];
	if ( _klen > 0 ) {
		int _lower = _keys;
		int _mid;
		int _upper = _keys + _klen - 1;
		while (true) {
			if ( _upper < _lower )
				break;

			_mid = _lower + ((_upper-_lower) >> 1);
			if ( data[p] < _http_parser_trans_keys[_mid] )
				_upper = _mid - 1;
			else if ( data[p] > _http_parser_trans_keys[_mid] )
				_lower = _mid + 1;
			else {
				_trans += (_mid - _keys);
				break _match;
			}
		}
		_keys += _klen;
		_trans += _klen;
	}

	_klen = _http_parser_range_lengths[cs];
	if ( _klen > 0 ) {
		int _lower = _keys;
		int _mid;
		int _upper = _keys + (_klen<<1) - 2;
		while (true) {
			if ( _upper < _lower )
				break;

			_mid = _lower + (((_upper-_lower) >> 1) & ~1);
			if ( data[p] < _http_parser_trans_keys[_mid] )
				_upper = _mid - 2;
			else if ( data[p] > _http_parser_trans_keys[_mid+1] )
				_lower = _mid + 2;
			else {
				_trans += ((_mid - _keys)>>1);
				break _match;
			}
		}
		_trans += _klen;
	}
	} while (false);

	_trans = _http_parser_indicies[_trans];
	cs = _http_parser_trans_targs_wi[_trans];

	if ( _http_parser_trans_actions_wi[_trans] == 0 )
		break _again;

	_acts = _http_parser_trans_actions_wi[_trans];
	_nacts = (int) _http_parser_actions[_acts++];
	while ( _nacts-- > 0 )
	{
		switch ( _http_parser_actions[_acts++] )
		{
	case 0:
// line 11 "org/jruby/mongrel/http11_parser.rl"
	{parser.mark = p; }
	break;
	case 1:
// line 13 "org/jruby/mongrel/http11_parser.rl"
	{ parser.field_start = p; }
	break;
	case 2:
// line 14 "org/jruby/mongrel/http11_parser.rl"
	{ 
    parser.field_len = p-parser.field_start;
  }
	break;
	case 3:
// line 18 "org/jruby/mongrel/http11_parser.rl"
	{ parser.mark = p; }
	break;
	case 4:
// line 19 "org/jruby/mongrel/http11_parser.rl"
	{ 
    if(parser.http_field != null) {
      parser.http_field.call(parser.data, parser.field_start, parser.field_len, parser.mark, p-parser.mark);
    }
  }
	break;
	case 5:
// line 24 "org/jruby/mongrel/http11_parser.rl"
	{ 
    if(parser.request_method != null) 
      parser.request_method.call(parser.data, parser.mark, p-parser.mark);
  }
	break;
	case 6:
// line 28 "org/jruby/mongrel/http11_parser.rl"
	{ 
    if(parser.request_uri != null)
      parser.request_uri.call(parser.data, parser.mark, p-parser.mark);
  }
	break;
	case 7:
// line 33 "org/jruby/mongrel/http11_parser.rl"
	{parser.query_start = p; }
	break;
	case 8:
// line 34 "org/jruby/mongrel/http11_parser.rl"
	{ 
    if(parser.query_string != null)
      parser.query_string.call(parser.data, parser.query_start, p-parser.query_start);
  }
	break;
	case 9:
// line 39 "org/jruby/mongrel/http11_parser.rl"
	{	
    if(parser.http_version != null)
      parser.http_version.call(parser.data, parser.mark, p-parser.mark);
  }
	break;
	case 10:
// line 44 "org/jruby/mongrel/http11_parser.rl"
	{
    if(parser.request_path != null)
      parser.request_path.call(parser.data, parser.mark, p-parser.mark);
  }
	break;
	case 11:
// line 49 "org/jruby/mongrel/http11_parser.rl"
	{ 
    parser.body_start = p + 1; 
    if(parser.header_done != null)
      parser.header_done.call(parser.data, p + 1, pe - p - 1);
    if (true) break _resume;
  }
	break;
// line 490 "org/jruby/mongrel/Http11Parser.java"
		}
	}

	} while (false);
	if ( cs == 0 )
		break _resume;
	if ( ++p == pe )
		break _resume;
	}
	}	}
	}
// line 166 "org/jruby/mongrel/http11_parser.rl"

     parser.cs = cs;
     parser.nread += (p - off);
     
     assert p <= pe                  : "buffer overflow after parsing execute";
     assert parser.nread <= len      : "nread longer than length";
     assert parser.body_start <= len : "body starts after buffer end";
     assert parser.mark < len        : "mark is after buffer end";
     assert parser.field_len <= len  : "field has length longer than whole buffer";
     assert parser.field_start < len : "field starts after buffer end";

     if(parser.body_start>0) {
        /* final \r\n combo encountered so stop right here */
        
// line 517 "org/jruby/mongrel/Http11Parser.java"
// line 180 "org/jruby/mongrel/http11_parser.rl"
        parser.nread++;
     }

     return parser.nread;
   }

   public int finish() {
     int cs = parser.cs;

     
// line 529 "org/jruby/mongrel/Http11Parser.java"
// line 190 "org/jruby/mongrel/http11_parser.rl"

     parser.cs = cs;
 
    if(has_error()) {
      return -1;
    } else if(is_finished()) {
      return 1;
    } else {
      return 0;
    }
  }

  public boolean has_error() {
    return parser.cs == http_parser_error;
  }

  public boolean is_finished() {
    return parser.cs == http_parser_first_final;
  }
}
