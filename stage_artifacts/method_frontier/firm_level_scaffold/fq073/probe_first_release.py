"""FQ-073 최초공표(first-release) 시점 실측 프로브.

probe_publication_lag.py 가 확정한 것은 '개정(현행화) 규약'(매월 15일경, 주기 1개월).
남은 미확정 = **최초공표 시점**(월 M 자료가 언제 처음 공개되는가). 이걸 문서 원문으로 확정한다.

수집:
  A. 15157901 상세 설명 전문 (10일 단위 잠정치 = 월중 속보 cadence 근거)
  B. 관세청 수출입무역통계 포털 tradedata.go.kr (공표 안내)
  C. 관세청 보도자료 목록(월간 수출입현황) — 발행일 패턴에서 시차 실측
출력: fq073/first_release_evidence.json
"""
import json, os, re, ssl, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "first_release_evidence.json")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def fetch(url, timeout=45):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Accept": "text/html,application/xhtml+xml,*/*",
        "Accept-Language": "ko-KR,ko;q=0.9",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s: %s" % (type(e).__name__, e)


def strip_tags(html):
    h = re.sub(r"(?is)<script.*?</script>", " ", html)
    h = re.sub(r"(?is)<style.*?</style>", " ", h)
    h = re.sub(r"(?s)<[^>]+>", " ", h)
    h = h.replace("&nbsp;", " ").replace("&amp;", "&")
    return re.sub(r"\s+", " ", h).strip()


res = {"probe": "FQ-073 first-release timing", "items": {}}

# ── A. 15157901 설명 전문 (10일 잠정치 cadence) ────────────────────────────
st, body = fetch("https://www.data.go.kr/data/15157901/openapi.do")
rec = {"url": "https://www.data.go.kr/data/15157901/openapi.do", "http_status": st}
if st == 200:
    txt = strip_tags(body)
    i = txt.find("tradedata.go.kr")
    rec["description_excerpt"] = txt[max(0, i - 400):i + 1400] if i > 0 else txt[:1500]
    rec["cadence_sentences"] = [s for s in re.split(r"○|●|\n", rec["description_excerpt"])
                                if any(k in s for k in ["주기", "공표", "제공범위", "잠정", "일 단위"])][:12]
res["items"]["15157901_desc"] = rec
print("[A 15157901] HTTP=%s" % st)
for s in rec.get("cadence_sentences", []):
    print("   |", s.strip()[:240])

# ── B. tradedata.go.kr (관세청 수출입무역통계 포털) ────────────────────────
for u in ["https://tradedata.go.kr/cts/index.do",
          "https://unipass.customs.go.kr/ets/index.do"]:
    st, body = fetch(u, timeout=30)
    txt = strip_tags(body) if st == 200 else body[:300]
    hits = [s for s in re.split(r"(?<=다\.)\s+|\|", txt)
            if any(k in s for k in ["잠정", "확정", "공표", "속보", "일자"])][:10] if st == 200 else []
    res["items"].setdefault("portal", []).append(
        {"url": u, "http_status": st, "hits": hits, "bytes": len(body)})
    print("[B %s] HTTP=%s hits=%d" % (u.split("/")[2], st, len(hits)))
    for h in hits[:5]:
        print("   |", h.strip()[:200])

# ── C. 관세청 보도자료(월간 수출입현황) 발행일 패턴 ────────────────────────
#     customs.go.kr 보도자료 목록에서 '수출입 현황' 제목 + 게시일 추출 → 시차 실측
for u in ["https://www.customs.go.kr/kcs/na/ntt/selectNttList.do?mi=2891&bbsId=1340",
          "https://www.customs.go.kr/kcs/cm/cntnts/cntntsView.do?mi=2891&cntntsId=815"]:
    st, body = fetch(u, timeout=30)
    rec = {"url": u, "http_status": st, "bytes": len(body)}
    if st == 200:
        txt = strip_tags(body)
        # "2026년 6월 월간 수출입 현황(확정치)" + 날짜 패턴 동시 포착
        rec["titles"] = re.findall(r"[^|]{0,40}수출입\s*현황[^|]{0,40}", txt)[:20]
        rec["dates"] = re.findall(r"20\d{2}[-.]\d{2}[-.]\d{2}", txt)[:20]
    res["items"].setdefault("press", []).append(rec)
    print("[C press] HTTP=%s titles=%d" % (st, len(rec.get("titles", []))))
    for t in rec.get("titles", [])[:8]:
        print("   |", t.strip()[:160])

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("\nsaved:", OUT)
