"""ECOS 대체로 실측: 성질별 수출입(901Y092) 품목 세분도 + 역사 depth."""
import urllib.request, urllib.error, ssl, json, os
CTX = ssl.create_default_context(); CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
EK = [l.strip().split("=", 1)[1].strip().strip('"')
      for l in open(os.path.join(ROOT, ".env"), encoding="utf-8")
      if l.strip().startswith("ECOS_API_KEY=")][0]

def get(u):
    r = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(r, timeout=45, context=CTX) as f:
            return f.status, f.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s" % e

for code in ["901Y092", "901Y121", "402Y016"]:
    st, b = get("https://ecos.bok.or.kr/api/StatisticItemList/%s/json/kr/1/500/%s" % (EK, code))
    try:
        rows = json.loads(b)["StatisticItemList"]["row"]
    except Exception:
        print("%s itemlist FAIL %s %s" % (code, st, b[:160])); continue
    print("=== %s  items=%d" % (code, len(rows)))
    print("    START/END(meta): %s ~ %s  cycle=%s"
          % (rows[0].get("START_TIME"), rows[0].get("END_TIME"), rows[0].get("CYCLE")))
    for r in rows[:14]:
        print("      %-14s %s" % (r.get("ITEM_CODE"), r.get("ITEM_NAME")))
    if len(rows) > 14: print("      ... (+%d)" % (len(rows) - 14))

# 역사 depth 실측: 성질별 수출입 2005-01 ~ 2026-06 월별
st, b = get("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/10/901Y092/M/200501/202606" % EK)
try:
    d = json.loads(b)["StatisticSearch"]
    print("\n901Y092 depth probe: total=%s" % d["list_total_count"])
    for r in d["row"][:6]:
        print("   %s %s %s %s" % (r.get("TIME"), r.get("ITEM_NAME1"), r.get("DATA_VALUE"), r.get("UNIT_NAME")))
except Exception:
    print("depth FAIL", st, b[:250])
