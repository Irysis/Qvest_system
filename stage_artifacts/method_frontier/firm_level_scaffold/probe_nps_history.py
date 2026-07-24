import os, urllib.parse, urllib.request, ssl, json
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
def load_key():
    with open(os.path.join(ROOT,".env"),"r",encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("DATA_GO_API_KEY="):
                return line.strip().split("=",1)[1].strip().strip('"').strip("'")
KEY = load_key()
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
B = "http://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2/"

def call(op, params):
    q = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    url = B+op+"?serviceKey="+KEY+"&"+q
    req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=40, context=ctx) as r:
            return r.status, r.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")
    except Exception as e:
        return -1, "EXC %r" % e

SEQ = "6514640"  # 삼성전자(주)

print("### H1. history param aliases on getDetailInfoSearchV2 (seq=%s) ###" % SEQ)
for name in ["dataCrtYm","data_crt_ym","baseYm","stdrYm","crtYm","searchYm"]:
    for ym in ["202401"]:
        st,b = call("getDetailInfoSearchV2", {"dataType":"json","seq":SEQ,name:ym})
        try:
            d=json.loads(b); it=d["response"]["body"]["items"]
            r0 = (it.get("item") or [{}])[0] if isinstance(it,dict) else {}
            print("  %-12s=%s -> HTTP %s returned dataCrtYm? jnngpCnt=%s ntc=%s"
                  % (name, ym, st, r0.get("jnngpCnt"), r0.get("crrmmNtcAmt")))
        except Exception:
            print("  %-12s=%s -> HTTP %s body=%s" % (name, ym, st, " ".join(b.split())[:160]))

print()
print("### H2. does the list op honor any month filter? (baseline vs filtered totalCount) ###")
base_params = {"pageNo":"1","numOfRows":"1","dataType":"json","wkplNm":"삼성전자(주)"}
st,b = call("getBassInfoSearchV2", base_params)
d=json.loads(b); print("  no-month  totalCount=", d["response"]["body"]["totalCount"])
for name in ["dataCrtYm","baseYm","stdrYm"]:
    p=dict(base_params); p[name]="202401"
    st,b = call("getBassInfoSearchV2", p)
    try:
        d=json.loads(b)
        it=d["response"]["body"]["items"]
        r0=(it.get("item") or [{}])[0] if isinstance(it,dict) else {}
        print("  %-10s=202401 totalCount=%s returned_dataCrtYm=%s"
              % (name, d["response"]["body"]["totalCount"], r0.get("dataCrtYm")))
    except Exception:
        print("  %-10s -> HTTP %s %s" % (name, st, " ".join(b.split())[:120]))

print()
print("### H3. sanity: a few more KOSPI names resolvable? ###")
for nm in ["에스케이하이닉스","현대자동차","엘지화학","네이버","기아"]:
    st,b = call("getBassInfoSearchV2", {"pageNo":"1","numOfRows":"5","dataType":"json","wkplNm":nm})
    try:
        d=json.loads(b); tc=d["response"]["body"]["totalCount"]
        it=d["response"]["body"]["items"]
        arr=it.get("item",[]) if isinstance(it,dict) else []
        names=[a.get("wkplNm") for a in arr][:3]
        print("  %-10s totalCount=%s sample=%s" % (nm, tc, names))
    except Exception:
        print("  %-10s HTTP %s %s" % (nm, st, " ".join(b.split())[:120]))
