"""FQ-073: (a) 정확 파라미터 재호출  (b) 관세청 GW 형제 데이터셋 swagger 수확"""
import urllib.request, urllib.error, re, ssl, json
from fq073_customs_probe import KEY_ENC, mask, CTX

def get(u):
    r = urllib.request.Request(u, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
        "Accept": "*/*", "Accept-Language": "ko-KR", "Referer": "https://www.data.go.kr/"})
    try:
        with urllib.request.urlopen(r, timeout=45, context=CTX) as f:
            return f.status, f.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s" % e

# ---------- (a) swagger 정확 규격 그대로 실호출 ----------
print("### (a) 정확-규격 실호출 (swagger param set, hsSgn=8542 반도체집적회로)")
for label, url in [
    ("Itemtrade_HSaggr", "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"
        "?serviceKey=" + KEY_ENC + "&strtYymm=202401&endYymm=202412&hsSgn=8542"),
    ("Itemtrade_noHS",   "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"
        "?serviceKey=" + KEY_ENC + "&strtYymm=201001&endYymm=201012"),
    ("Itemtrade_2010",   "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"
        "?serviceKey=" + KEY_ENC + "&strtYymm=201001&endYymm=201012&hsSgn=85"),
]:
    st, b = get(url)
    print("  %-18s HTTP=%-4s BODY=%s" % (label, st, mask(re.sub(r"\s+", " ", b)).strip()[:220]))

# ---------- (b) 형제 데이터셋 swagger ----------
print("\n### (b) 관세청(1220000) 형제 데이터셋 swagger 수확")
PKS = {
    "15101609": "품목별 수출입실적(GW)",
    "15100475": "품목별 국가별 수출입실적(GW)",
    "15101612": "국가별 수출입실적(GW)",
    "15102108": "수출입총괄(GW)",
    "15101641": "시도별 품목별 수출입실적(GW)",
    "15134343": "시군구별 품목별 수출입실적",
    "15157901": "수입 주요품목별 10일 단위 잠정치",
    "15101643": "시도별 수출입실적(GW)",
    "15101632": "경제권별 수출입실적(GW)",
}
out = {}
for pk, nm in PKS.items():
    st, h = get("https://www.data.go.kr/data/%s/openapi.do" % pk)
    if st != 200:
        print("  pk=%s %-28s page HTTP=%s" % (pk, nm, st)); continue
    m = re.search(r"var swaggerJson = `(.+?)`;", h, flags=re.S)
    if not m:
        print("  pk=%s %-28s swaggerJson 미발견" % (pk, nm)); continue
    try:
        # JS 템플릿 리터럴 언이스케이프: `\\` -> `\` 먼저, 그 다음 JSON 파싱
        sw = json.loads(m.group(1).replace("\\\\", "\\"))
    except Exception as e:
        print("  pk=%s parse fail %s" % (pk, e)); continue
    host = sw.get("host", "")
    for path, ops in sw.get("paths", {}).items():
        prm = [(p["name"], "REQ" if p.get("required") else "opt") for p in ops.get("parameters", [])]
        g = ops.get("get", {})
        fields = []
        try:
            fields = list(g["responses"]["200"]["schema"]["properties"]["body"]["properties"]
                          ["items"]["properties"]["item"]["properties"].keys())
        except Exception:
            pass
        print("  pk=%s %-28s https://%s%s" % (pk, nm, host, path))
        print("        params: %s" % ", ".join("%s(%s)" % x for x in prm))
        print("        fields: %s" % ", ".join(fields))
        out[pk] = {"name": nm, "endpoint": "https://%s%s" % (host, path),
                   "params": prm, "fields": fields}
json.dump(out, open("fq073_customs_api_catalog.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("\nsaved -> fq073_customs_api_catalog.json (%d entries)" % len(out))
