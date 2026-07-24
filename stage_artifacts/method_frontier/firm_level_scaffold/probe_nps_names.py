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

# for the misses: search the bare token, list candidates with NO '/' (parent-like), big jnngpCnt
for token in ["에스케이하이닉스","케이비금융지주","셀트리온","포스코홀딩스"]:
    st,b=call("getBassInfoSearchV2",{"pageNo":"1","numOfRows":"100","dataType":"json","wkplNm":token})
    tc,arr=items(b)
    cand=[a for a in arr if "/" not in a.get("wkplNm","") and "(" not in a.get("wkplNm","")[:1]]
    print("== %s  totalCount=%s ==" % (token, tc))
    shown=0
    for a in cand:
        st2,b2=call("getDetailInfoSearchV2",{"dataType":"json","seq":str(a["seq"])})
        _,d=items(b2)
        if not d: continue
        r=d[0]; jn=r.get("jnngpCnt") or 0
        if jn >= 300:
            print("   %-34s jnngpCnt=%-7s bizno=%s adptDt=%s ind=%s"
                  % (r.get("wkplNm"), jn, r.get("bzowrRgstNo"), r.get("adptDt"), r.get("vldtVlKrnNm")))
            shown+=1
        if shown>=4: break
    if shown==0: print("   (no parent-like record with jnngpCnt>=300 in first 100 substring hits)")
