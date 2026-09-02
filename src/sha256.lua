local SHA256={}
local MOD=4294967296
local function norm(a) return a%MOD end
local BAND4,BXOR4={},{}
for a=0,15 do
  BAND4[a],BXOR4[a]={},{}
  for b=0,15 do
    local andValue,xorValue,p,left,right=0,0,1,a,b
    for _=1,4 do
      local aa,bb=left%2,right%2
      if aa==1 and bb==1 then andValue=andValue+p end
      if aa~=bb then xorValue=xorValue+p end
      left=(left-aa)/2; right=(right-bb)/2; p=p*2
    end
    BAND4[a][b],BXOR4[a][b]=andValue,xorValue
  end
end
local unpackValues=table.unpack or unpack
local BAND8,BXOR8={},{}
for a=0,255 do
  local andBytes,xorBytes={},{}
  local aLow,aHigh=a%16,math.floor(a/16)
  for b=0,255 do
    local bLow,bHigh=b%16,math.floor(b/16)
    andBytes[b+1]=BAND4[aLow][bLow]+16*BAND4[aHigh][bHigh]
    xorBytes[b+1]=BXOR4[aLow][bLow]+16*BXOR4[aHigh][bHigh]
  end
  BAND8[a]=string.char(unpackValues(andBytes))
  BXOR8[a]=string.char(unpackValues(xorBytes))
end
local function bitwise2(a,b,lookup)
  local r,p=0,1; a,b=norm(a),norm(b)
  for _=1,4 do
    local aa,bb=a%256,b%256
    r=r+lookup[aa]:byte(bb+1)*p
    a=(a-aa)/256; b=(b-bb)/256; p=p*256
  end
  return r
end
local function band2(a,b) return bitwise2(a,b,BAND8) end
local function bxor2(a,b) return bitwise2(a,b,BXOR8) end
local function bxor(...) local values={...}; local r=0; for i=1,#values do r=bxor2(r,values[i]) end; return r end
local function bnot(a) return MOD-1-norm(a) end
local function rshift(a,n) return math.floor(norm(a)/2^n) end
local function rrotate(a,n) n=n%32; if n==0 then return norm(a) end; return norm(rshift(a,n)+(norm(a)%2^n)*2^(32-n)) end
local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
function SHA256.hex(message)
  assert(type(message)=="string","SHA256.hex expects a string")
  local bits=#message*8; message=message..string.char(0x80); local padding=(56-(#message%64))%64; message=message..string.rep("\0",padding)
  local high=math.floor(bits/MOD); local low=bits%MOD
  local function be32(n) return string.char(rshift(n,24)%256,rshift(n,16)%256,rshift(n,8)%256,n%256) end
  message=message..be32(high)..be32(low)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset=1,#message,64 do
    local w={}; for i=0,15 do local p=offset+i*4; local a,b,c,d=message:byte(p,p+3); w[i+1]=a*16777216+b*65536+c*256+d end
    for i=17,64 do local x=w[i-15]; local y=w[i-2]; local s0=bxor(rrotate(x,7),rrotate(x,18),rshift(x,3)); local s1=bxor(rrotate(y,17),rrotate(y,19),rshift(y,10)); w[i]=norm(w[i-16]+s0+w[i-7]+s1) end
    local a,b,c,d,e,f,g,hh=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i=1,64 do local s1=bxor(rrotate(e,6),rrotate(e,11),rrotate(e,25)); local ch=bxor(band2(e,f),band2(bnot(e),g)); local t1=norm(hh+s1+ch+K[i]+w[i]); local s0=bxor(rrotate(a,2),rrotate(a,13),rrotate(a,22)); local maj=bxor(band2(a,b),band2(a,c),band2(b,c)); local t2=norm(s0+maj); hh=g;g=f;f=e;e=norm(d+t1);d=c;c=b;b=a;a=norm(t1+t2) end
    h[1]=norm(h[1]+a);h[2]=norm(h[2]+b);h[3]=norm(h[3]+c);h[4]=norm(h[4]+d);h[5]=norm(h[5]+e);h[6]=norm(h[6]+f);h[7]=norm(h[7]+g);h[8]=norm(h[8]+hh)
  end
  local out={}; for i=1,8 do out[i]=string.format("%08x",h[i]) end; return table.concat(out)
end
return SHA256
