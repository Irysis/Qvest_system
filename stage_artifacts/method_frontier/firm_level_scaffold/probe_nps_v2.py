import os, sys, urllib.parse, urllib.request, ssl, json, re

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

def load_key():
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("DATA_GO_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("key not found")

KEY = load_key()

def mask(s):
    # never leak the key
    return s.replace(KEY, "<KEY>").replace(urllib.parse.quote(KEY, safe=""), "<KEY>")

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def call(base, params, label, encode_key=False):
    p = dict(params)
    q = urllib.parse.urlencode(p, quote_via=urllib.parse.quote)
    sk = urllib.parse.quote(KEY, safe="") if encode_key else KEY
    url = base + "?serviceKey=" + sk + "&" + q
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
            body = r.read().decode("utf-8", "replace")
            status = r.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        status = e.code
    except Exception as e:
        body = "EXC: %r" % e
        status = -1
    print("=" * 78)
    print("[%s] HTTP %s" % (label, status))
    print("URL: " + mask(url))
    print("BODY[:1400]: " + mask(body[:1400]).replace("\n", " ")[:1400])
    return status, body

BASE = "http://apis.data.go.kr/B552015"

TESTS = [
    # 1. 가입 사업장 내역 V2 (firm-level) - the FQ-064 target
    ("bplc_v2_json", BASE + "/NpsBplcInfoInqireServiceV2/getBassInfoSearchV2",
     {"pageNo": "1", "numOfRows": "3", "dataType": "json"}),
    ("bplc_v2_xml", BASE + "/NpsBplcInfoInqireServiceV2/getBassInfoSearchV2",
     {"pageNo": "1", "numOfRows": "3"}),
    # 2. 가입현황 V2 (aggregate stats)
    ("sbscrb_v2_json", BASE + "/NpsSbscrbInfoProvdServiceV2/getSbscrbSttusInfoSearchV2",
     {"pageNo": "1", "numOfRows": "3", "dataType": "json"}),
    # 3. 탈퇴 사업장 V2
    ("scsn_bplc_v2", BASE + "/NpsScsnBplcInfoInqireServiceV2/getBassInfoSearchV2",
     {"pageNo": "1", "numOfRows": "3", "dataType": "json"}),
    # 4. V1 legacy control (expected dead)
    ("bplc_v1_legacy", BASE + "/NpsBplcInfoInqireService/getBassInfoSearch",
     {"pageNo": "1", "numOfRows": "3"}),
]

results = {}
for label, base, params in TESTS:
    st, body = call(base, params, label + "|rawkey", encode_key=False)
    results[label] = st
    if st != 200 or ("errMsg" in body or "SERVICE ERROR" in body or "returnAuthMsg" in body):
        st2, body2 = call(base, params, label + "|encodedkey", encode_key=True)
        results[label + "_enc"] = st2

# https scheme retry on the primary target
call("https://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2/getBassInfoSearchV2",
     {"pageNo": "1", "numOfRows": "3", "dataType": "json"}, "bplc_v2_HTTPS|rawkey")

print("=" * 78)
print("SUMMARY:", json.dumps(results))
