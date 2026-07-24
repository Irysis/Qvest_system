"""FQ-073 승인-후 1커맨드 실측 프로브.

도훈이 data.go.kr 15101609 활용신청(개발단계 자동승인)을 누른 뒤 이 스크립트 1회 실행.
403 -> 200 전환을 확인하고, 미측정 3항목(역사 depth / HS 자릿수 거동 / 행수)을 실측한다.

실행:
  cd stage_artifacts/method_frontier/firm_level_scaffold
  ../../../.venv_qvest_ml/Scripts/python.exe fq073_probe_after_approval.py
"""
import re, urllib.request, urllib.error
from fq073_customs_probe import KEY_ENC, mask, CTX

BASE = "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"

def call(strt, end, hs=None):
    u = "%s?serviceKey=%s&strtYymm=%s&endYymm=%s" % (BASE, KEY_ENC, strt, end)
    if hs is not None:
        u += "&hsSgn=%s" % hs
    r = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(r, timeout=45, context=CTX) as f:
            return f.status, f.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s" % e

def summarize(st, body):
    items = re.findall(r"<item>(.*?)</item>", body, flags=re.S)
    msg = re.search(r"<resultMsg>(.*?)</resultMsg>", body)
    return st, (msg.group(1) if msg else "?"), len(items), items[:1]

print("=== 0) 승인 확인 ===")
st, b = call("202401", "202412", "8542")
print("HTTP=%s  %s" % (st, mask(re.sub(r"\s+", " ", b)).strip()[:200]))
if st != 200:
    raise SystemExit("아직 미승인(403) 또는 오류 — 활용신청 승인 후 재실행")

print("\n=== 1) 역사 depth: 연도별 최소 시작점 탐색 ===")
for y in [1995, 2000, 2005, 2008, 2010, 2013, 2016, 2020]:
    st, b = call("%d01" % y, "%d12" % y, "85")
    s, m, n, ex = summarize(st, b)
    print("  %d: HTTP=%s msg=%s rows=%d" % (y, s, m, n))

print("\n=== 2) HS 자릿수 거동 (2/4/6/10단위 + 생략) ===")
for hs in [None, "85", "8542", "854231", "8542310000"]:
    st, b = call("202401", "202412", hs)
    s, m, n, ex = summarize(st, b)
    print("  hsSgn=%-11s HTTP=%s rows=%d" % (str(hs), s, n))
    if ex:
        print("     sample:", re.sub(r"\s+", " ", ex[0])[:240])

print("\n=== 3) 1년 초과 윈도우 거동 (제약 실증) ===")
st, b = call("202301", "202412", "85")
s, m, n, ex = summarize(st, b)
print("  2023-01~2024-12: HTTP=%s msg=%s rows=%d" % (s, m, n))
