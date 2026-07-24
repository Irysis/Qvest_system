import os, urllib.parse, urllib.request, ssl, json

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

def load_key():
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("DATA_GO_API_KEY="):
                return line.strip().split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("key not found")

KEY = load_key()
def mask(s):
    return s.replace(KEY, "<KEY>").replace(urllib.parse.quote(KEY, safe=""), "<KEY>")

ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
B = "http://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2/"

def call(op, params, label, show=900):
    q = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    url = B + op + "?serviceKey=" + KEY + "&" + q
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
            body = r.read().decode("utf-8", "replace"); status = r.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace"); status = e.code
    except Exception as e:
        body = "EXC: %r" % e; status = -1
    flat = " ".join(body.split())
    print("-" * 76)
    print("[%s] HTTP %s | op=%s | params=%s" % (label, status, op, {k: v for k, v in params.items()}))
    print("  " + mask(flat[:show]))
    return status, body

print("###### A. getBassInfoSearchV2 with search filters ######")
# V1 snake_case names, V2 camelCase per migration notice
cand = [
    ("wkplNm_samsung",  {"pageNo":"1","numOfRows":"3","dataType":"json","wkplNm":"삼성전자"}),
    ("wkpl_nm_snake",   {"pageNo":"1","numOfRows":"3","dataType":"json","wkpl_nm":"삼성전자"}),
    ("ldongDgCd_11",    {"pageNo":"1","numOfRows":"3","dataType":"json","ldongAddrMgplDgCd":"11"}),
    ("ldong_snake_11",  {"pageNo":"1","numOfRows":"3","dataType":"json","ldong_addr_mgpl_dg_cd":"11"}),
    ("bzowrRgstNo",     {"pageNo":"1","numOfRows":"3","dataType":"json","bzowrRgstNo":"124"}),
    ("dgSggu_11_680",   {"pageNo":"1","numOfRows":"3","dataType":"json",
                         "ldongAddrMgplDgCd":"11","ldongAddrMgplSgguCd":"11680"}),
]
for lab, p in cand:
    call("getBassInfoSearchV2", p, lab)

print()
print("###### B. other operations ######")
for op in ["getDetailInfoSearchV2", "getPdAcctoSttusInfoSearchV2", "getBassInfoSearch"]:
    call(op, {"pageNo":"1","numOfRows":"3","dataType":"json"}, "op_" + op)
