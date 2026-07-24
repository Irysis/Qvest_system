import os, urllib.parse, urllib.request, ssl, json

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
def load_key():
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("DATA_GO_API_KEY="):
                return line.strip().split("=", 1)[1].strip().strip('"').strip("'")
KEY = load_key()
def mask(s): return s.replace(KEY, "<KEY>")
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
B = "http://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2/"

def call(op, params, label, show=1500, quiet=False):
    q = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    url = B + op + "?serviceKey=" + KEY + "&" + q
    req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=40, context=ctx) as r:
            body = r.read().decode("utf-8","replace"); status = r.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8","replace"); status = e.code
    except Exception as e:
        body = "EXC: %r" % e; status = -1
    if not quiet:
        print("-"*76)
        print("[%s] HTTP %s | op=%s | %s" % (label, status, op, params))
        print("  " + mask(" ".join(body.split()))[:show])
    return status, body

def js(body):
    try: return json.loads(body)
    except Exception: return None

# --- 1. find 삼성전자 the actual listed corp ---
print("###### 1. locate listed corp (주식회사 삼성전자) ######")
st, b = call("getBassInfoSearchV2",
    {"pageNo":"1","numOfRows":"100","dataType":"json","wkplNm":"삼성전자","ldongAddrMgplDgCd":"41"},
    "search_samsung_gg", show=200)
d = js(b)
target = None
if d:
    items = d["response"]["body"]["items"]
    arr = items.get("item", []) if isinstance(items, dict) else []
    print("  totalCount=", d["response"]["body"]["totalCount"], " returned=", len(arr))
    for it in arr:
        nm = it.get("wkplNm","")
        if nm.strip() in ("주식회사 삼성전자","삼성전자주식회사","삼성전자(주)","(주)삼성전자","삼성전자 주식회사"):
            target = it; break
    if target is None:
        for it in arr:
            if "/" not in it.get("wkplNm",""):
                target = it; break
    print("  PICKED:", json.dumps(target, ensure_ascii=False))

seq = str(target["seq"]) if target else "7103978"

# --- 2. detail op param probes ---
print()
print("###### 2. getDetailInfoSearchV2 param probes (seq) ######")
for lab, p in [
    ("seq",        {"dataType":"json","seq":seq}),
    ("seq+ldong",  {"dataType":"json","seq":seq,
                    "ldongAddrMgplDgCd":str(target["ldongAddrMgplDgCd"]) if target else "41",
                    "ldongAddrMgplSgguCd":str(target["ldongAddrMgplSgguCd"]) if target else "220",
                    "ldongAddrMgplSgguEmdCd":str(target["ldongAddrMgplSgguEmdCd"]) if target else "128",
                    "wkplJnngStcd":str(target["wkplJnngStcd"]) if target else "1"}),
]:
    call("getDetailInfoSearchV2", p, "detail_"+lab)

# --- 3. period status op (the FQ-064 time series) ---
print()
print("###### 3. getPdAcctoSttusInfoSearchV2 param probes ######")
for lab, p in [
    ("seq_only",   {"dataType":"json","seq":seq,"pageNo":"1","numOfRows":"10"}),
    ("seq_dataCrtYm", {"dataType":"json","seq":seq,"dataCrtYm":"202606","pageNo":"1","numOfRows":"10"}),
]:
    call("getPdAcctoSttusInfoSearchV2", p, "pd_"+lab)

# --- 4. history: can we pull past months on the list op? ---
print()
print("###### 4. history probe: dataCrtYm on getBassInfoSearchV2 ######")
for ym in ["202606","202512","202401","202001"]:
    st, b = call("getBassInfoSearchV2",
        {"pageNo":"1","numOfRows":"1","dataType":"json","ldongAddrMgplDgCd":"11","dataCrtYm":ym},
        "hist_"+ym, quiet=True)
    d2 = js(b)
    tc = d2["response"]["body"]["totalCount"] if d2 else "?"
    it = d2["response"]["body"]["items"] if d2 else {}
    got = ""
    if isinstance(it, dict) and it.get("item"):
        r0 = it["item"][0] if isinstance(it["item"], list) else it["item"]
        got = "dataCrtYm_returned=" + str(r0.get("dataCrtYm"))
    print("  req dataCrtYm=%s -> HTTP %s totalCount=%s %s" % (ym, st, tc, got))
