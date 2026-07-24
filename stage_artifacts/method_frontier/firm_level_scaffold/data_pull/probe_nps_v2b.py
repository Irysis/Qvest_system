"""Probe NPS V2 seq-based ops: history depth + headcount. Key always masked."""
import os, sys, json, urllib.parse, urllib.request, ssl

ROOT = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
key = None
with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if line.startswith("DATA_GO_API_KEY"):
            key = line.split("=", 1)[1].strip().strip('"').strip("'")
            break
if not key:
    print("NO KEY"); sys.exit(1)


def mask(s):
    for v in {key, urllib.parse.quote(key, safe=""), urllib.parse.unquote(key)}:
        s = s.replace(v, "<KEY>")
    return s


ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
V2 = "https://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2"


def call(label, path, params, show=1200):
    url = V2 + path + "?" + urllib.parse.urlencode(
        dict(params, serviceKey=urllib.parse.unquote(key)), quote_via=urllib.parse.quote)
    print("\n=== %s ===" % label)
    print("URL: " + mask(url))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=45, context=ctx) as r:
            b = r.read().decode("utf-8", "replace")
            print("HTTP=%d" % r.status); print(mask(b[:show])); return b
    except urllib.error.HTTPError as e:
        b = e.read().decode("utf-8", "replace")
        print("HTTP=%d" % e.code); print(mask(b[:show])); return b
    except Exception as e:
        print("EXC " + mask(str(e))); return ""


# Find the actual listed firm 삼성전자 (not subcontractor sites)
b = call("search exact 삼성전자주식회사", "/getBassInfoSearchV2",
         {"wkplNm": "삼성전자주식회사", "numOfRows": "5", "pageNo": "1", "dataType": "JSON"})
seq = None
try:
    items = json.loads(b)["response"]["body"]["items"]["item"]
    if isinstance(items, dict):
        items = [items]
    seq = str(items[0]["seq"])
    print("\n>>> picked seq=%s  name=%s" % (seq, items[0].get("wkplNm")))
except Exception as e:
    print("parse fail: %s" % e)

if seq:
    call("getDetailInfoSearchV2 seq=%s" % seq, "/getDetailInfoSearchV2",
         {"seq": seq, "numOfRows": "10", "pageNo": "1", "dataType": "JSON"})
    # history probe: no dataCrtYm -> how much back?
    call("getPdAcctoSttusInfoSearchV2 seq=%s NO dataCrtYm" % seq, "/getPdAcctoSttusInfoSearchV2",
         {"seq": seq, "numOfRows": "100", "pageNo": "1", "dataType": "JSON"}, show=2000)
    for ym in ["202606", "202401", "202001", "201601"]:
        call("getPdAcctoSttusInfoSearchV2 seq=%s ym=%s" % (seq, ym), "/getPdAcctoSttusInfoSearchV2",
             {"seq": seq, "dataCrtYm": ym, "numOfRows": "10", "pageNo": "1", "dataType": "JSON"}, show=700)
