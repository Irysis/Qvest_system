"""FQ-073 대안로: ECOS(보유키)에 HS/품목별 수출 통계가 있는지 실측."""
import urllib.request, urllib.error, re, ssl, json, os
CTX = ssl.create_default_context(); CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

def load(name):
    for line in open(os.path.join(ROOT, ".env"), encoding="utf-8"):
        if line.strip().startswith(name + "="):
            return line.strip().split("=", 1)[1].strip().strip('"').strip("'")
    return None

EK = load("ECOS_API_KEY")
def mask(s): return s.replace(EK, "<ECOS_KEY>") if EK else s

def get(u):
    r = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(r, timeout=45, context=CTX) as f:
            return f.status, f.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s" % e

print("ECOS key present:", bool(EK))
st, b = get("https://ecos.bok.or.kr/api/StatisticTableList/%s/json/kr/1/2000/" % EK)
print("StatisticTableList HTTP=%s len=%d" % (st, len(b)))
try:
    j = json.loads(b)
except Exception as e:
    print("parse fail", mask(b)[:300]); raise SystemExit

rows = j.get("StatisticTableList", {}).get("row", [])
print("total tables:", len(rows))
hits = [r for r in rows if any(k in (r.get("STAT_NAME", "") + r.get("P_STAT_NAME", ""))
                               for k in ("수출", "수입", "무역", "통관"))]
print("\n-- 수출/수입/무역/통관 포함 통계표 (%d) --" % len(hits))
for r in hits:
    print("  %-12s cycle=%-4s %s" % (r.get("STAT_CODE"), r.get("CYCLE"), r.get("STAT_NAME")))
json.dump(hits, open("fq073_ecos_trade_tables.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
