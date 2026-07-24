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
def call(op,params,to=60):
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

print("### are duplicate records = monthly vintages, or different sites? ###")
st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"20","dataType":"json","wkplNm":"포스코홀딩스"})
tc,arr=items(b)
print("totalCount=",tc)
for a in arr:
    if a.get("wkplNm","").strip()!="포스코홀딩스": continue
    st2,b2=call("getDetailInfoSearchV2",{"dataType":"json","seq":str(a["seq"])})
    _,d=items(b2); r=d[0] if d else {}
    print("  seq=%-9s dataCrtYm=%s ldong=%s/%s/%s jnngpCnt=%-6s ntcAmt=%-13s addr=%s"
          % (a["seq"], a.get("dataCrtYm"), a.get("ldongAddrMgplDgCd"), a.get("ldongAddrMgplSgguCd"),
             a.get("ldongAddrMgplSgguEmdCd"), r.get("jnngpCnt"), r.get("crrmmNtcAmt"),
             a.get("wkplRoadNmDtlAddr")))

print()
print("### same for 에스케이하이닉스 주식회사 ###")
st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"60","dataType":"json","wkplNm":"에스케이하이닉스 주식회사"})
tc,arr=items(b)
print("totalCount=",tc)
for a in arr:
    if a.get("wkplNm","").strip()!="에스케이하이닉스 주식회사": continue
    st2,b2=call("getDetailInfoSearchV2",{"dataType":"json","seq":str(a["seq"])})
    _,d=items(b2); r=d[0] if d else {}
    print("  seq=%-9s dataCrtYm=%s ldong=%s/%s/%s jnngpCnt=%-6s addr=%s"
          % (a["seq"], a.get("dataCrtYm"), a.get("ldongAddrMgplDgCd"), a.get("ldongAddrMgplSgguCd"),
             a.get("ldongAddrMgplSgguEmdCd"), r.get("jnngpCnt"), a.get("wkplRoadNmDtlAddr")))
