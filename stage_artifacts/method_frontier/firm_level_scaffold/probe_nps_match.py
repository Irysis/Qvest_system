import os, urllib.parse, urllib.request, ssl, json
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
def load_key():
    with open(os.path.join(ROOT,".env"),"r",encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("DATA_GO_API_KEY="):
                return line.strip().split("=",1)[1].strip().strip('"').strip("'")
KEY=load_key()
ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
B="http://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2/"
def call(op,params):
    q=urllib.parse.urlencode(params,quote_via=urllib.parse.quote)
    req=urllib.request.Request(B+op+"?serviceKey="+KEY+"&"+q,headers={"User-Agent":"Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req,timeout=40,context=ctx) as r: return r.status,r.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e: return e.code,e.read().decode("utf-8","replace")
    except Exception as e: return -1,"EXC %r"%e

def items(b):
    try:
        d=json.loads(b); it=d["response"]["body"]["items"]
        arr=it.get("item",[]) if isinstance(it,dict) else []
        if isinstance(arr,dict): arr=[arr]
        return d["response"]["body"]["totalCount"], arr
    except Exception: return None,[]

print("### M1. exact-name resolution for KOSPI parents (parent corp = no '/' in wkplNm) ###")
KOSPI=["삼성전자(주)","에스케이하이닉스(주)","(주)에스케이하이닉스","현대자동차(주)","(주)엘지화학",
       "엘지화학(주)","(주)기아","네이버(주)","(주)네이버","주식회사 카카오","삼성바이오로직스(주)",
       "(주)포스코홀딩스","케이비금융지주","셀트리온(주)"]
hits=[]
for nm in KOSPI:
    st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"20","dataType":"json","wkplNm":nm})
    tc,arr=items(b)
    exact=[a for a in arr if a.get("wkplNm","").strip()==nm]
    tag="EXACT" if exact else ("partial" if arr else "NONE")
    print("  %-20s tc=%-6s %-7s %s" % (nm, tc, tag,
          (exact[0]["wkplNm"]+" seq="+str(exact[0]["seq"])) if exact else [a.get("wkplNm") for a in arr[:2]]))
    if exact: hits.append(exact[0])

print()
print("### M2. detail pull for exact hits (the FQ-064 payload) ###")
for h in hits:
    st,b=call("getDetailInfoSearchV2",{"dataType":"json","seq":str(h["seq"])})
    tc,arr=items(b)
    if arr:
        r=arr[0]
        jn=r.get("jnngpCnt"); amt=int(r.get("crrmmNtcAmt") or 0)
        st2,b2=call("getPdAcctoSttusInfoSearchV2",{"dataType":"json","seq":str(h["seq"])})
        _,arr2=items(b2); flow=arr2[0] if arr2 else {}
        avg = (amt/jn/0.09/10000) if jn else 0   # 9% 보험료율 -> 월평균 기준소득 (만원)
        print("  %-20s jnngpCnt=%-8s ntcAmt=%-14s avgIncome~%.0f만 new=%s lost=%s bizno=%s ind=%s"
              % (r.get("wkplNm"), jn, amt, avg, flow.get("nwAcqzrCnt"), flow.get("lssJnngpCnt"),
                 r.get("bzowrRgstNo"), r.get("vldtVlKrnNm")))

print()
print("### M3. bzowrRgstNo masking check (is it usable as a join key?) ###")
st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"5","dataType":"json","ldongAddrMgplDgCd":"11"})
_,arr=items(b)
for a in arr[:5]:
    v=a.get("bzowrRgstNo","")
    print("  bzowrRgstNo=%s len=%d visible_digits=%d" % (v, len(v), sum(c.isdigit() for c in v)))
