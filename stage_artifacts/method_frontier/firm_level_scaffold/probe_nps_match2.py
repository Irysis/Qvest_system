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
def call(op,params,to=25):
    q=urllib.parse.urlencode(params,quote_via=urllib.parse.quote)
    req=urllib.request.Request(B+op+"?serviceKey="+KEY+"&"+q,headers={"User-Agent":"Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req,timeout=to,context=ctx) as r: return r.status,r.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e: return e.code,e.read().decode("utf-8","replace")
    except Exception as e: return -1,"EXC %r"%e
def items(b):
    try:
        d=json.loads(b); it=d["response"]["body"]["items"]
        arr=it.get("item",[]) if isinstance(it,dict) else []
        if isinstance(arr,dict): arr=[arr]
        return d["response"]["body"]["totalCount"], arr
    except Exception: return None,[]

print("### exact-name resolution + full payload for KOSPI parents ###")
for nm in ["삼성전자(주)","에스케이하이닉스(주)","현대자동차(주)","(주)엘지화학","(주)기아"]:
    st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"20","dataType":"json","wkplNm":nm})
    tc,arr=items(b)
    exact=[a for a in arr if a.get("wkplNm","").strip()==nm]
    if not exact:
        print("  %-16s HTTP %s tc=%s -> NO EXACT (sample=%s)" % (nm, st, tc, [a.get("wkplNm") for a in arr[:2]]))
        continue
    h=exact[0]
    st2,b2=call("getDetailInfoSearchV2",{"dataType":"json","seq":str(h["seq"])})
    _,d=items(b2)
    st3,b3=call("getPdAcctoSttusInfoSearchV2",{"dataType":"json","seq":str(h["seq"])})
    _,f=items(b3)
    r=d[0] if d else {}; fl=f[0] if f else {}
    jn=r.get("jnngpCnt") or 0; amt=int(r.get("crrmmNtcAmt") or 0)
    avg=(amt/jn/0.09/10000) if jn else 0
    print("  %-16s seq=%-9s jnngpCnt=%-7s ntcAmt=%-13s avgIncome~%.0f만 new=%-5s lost=%-5s bizno=%s adptDt=%s ind=%s"
          % (r.get("wkplNm"), h["seq"], jn, amt, avg, fl.get("nwAcqzrCnt"), fl.get("lssJnngpCnt"),
             r.get("bzowrRgstNo"), r.get("adptDt"), r.get("vldtVlKrnNm")))
