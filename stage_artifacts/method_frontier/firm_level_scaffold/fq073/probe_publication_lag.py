"""FQ-073 발표시차(publication lag) 실측 프로브 — 문서 근거 수집.

목적: 관세청 수출입실적 통계의 (a) 최초공표 시차 (b) 개정(현행화) 규약을
      **문서 원문 HTTP 응답**으로 확정한다. 추측 금지 — 근거 문장을 그대로 인용 저장.

수집 대상:
  1. data.go.kr 15101609 (품목별 수출입실적) 상세페이지 — 설명·업데이트주기
  2. data.go.kr 15157901 (수입 주요품목별 10일단위 잠정치) — 순별 잠정 cadence
  3. data.go.kr 15100475 (품목별 국가별) — 동일 현행화 문구 교차확인
  4. 관세청 수출입무역통계 포털(tradedata.go.kr) 공표 안내(접근 가능 시)

출력: fq073/publication_lag_evidence.json  (HTTP status + 근거 문장 원문)
실행: ../../../../.venv_qvest_ml/Scripts/python.exe probe_publication_lag.py
"""
import json, os, re, ssl, urllib.request, urllib.error

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "publication_lag_evidence.json")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

TARGETS = [
    ("15101609", "https://www.data.go.kr/data/15101609/openapi.do"),
    ("15157901", "https://www.data.go.kr/data/15157901/openapi.do"),
    ("15100475", "https://www.data.go.kr/data/15100475/openapi.do"),
    ("15102108", "https://www.data.go.kr/data/15102108/openapi.do"),
]

# 시차·개정 관련 키워드(원문 문장 추출용)
KEYS = ["현행화", "정정", "취하", "잠정", "확정", "매월", "공표", "업데이트", "갱신주기",
        "수정일", "제공주기", "주기", "일경", "익월", "속보"]


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
    h = h.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", h).strip()


def sentences_with_keys(text):
    hits = []
    for sent in re.split(r"(?<=[.。!?])\s+|(?<=다\.)\s+|\n", text):
        s = sent.strip()
        if not s or len(s) > 600:
            continue
        if any(k in s for k in KEYS):
            hits.append(s)
    # 중복 제거(순서 보존)
    seen, out = set(), []
    for h in hits:
        if h not in seen:
            seen.add(h)
            out.append(h)
    return out


def field_after(text, label, width=160):
    """상세페이지 표의 '라벨 값' 패턴에서 값 추출."""
    i = text.find(label)
    if i < 0:
        return None
    return text[i:i + width].strip()


result = {"probe": "FQ-073 publication lag", "targets": {}}

for did, url in TARGETS:
    st, body = fetch(url)
    rec = {"url": url, "http_status": st, "bytes": len(body)}
    if st == 200:
        txt = strip_tags(body)
        rec["evidence_sentences"] = sentences_with_keys(txt)[:40]
        for lab in ["업데이트 주기", "수정일", "등록일", "제공형태", "차기 등록 예정일", "비용부과유무"]:
            v = field_after(txt, lab)
            if v:
                rec.setdefault("fields", {})[lab] = v
    else:
        rec["body_head"] = body[:300]
    result["targets"][did] = rec
    print("[%s] HTTP=%s bytes=%s" % (did, st, len(body)))
    for s in rec.get("evidence_sentences", [])[:8]:
        print("    | %s" % s[:220])

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print("\nsaved:", OUT)
