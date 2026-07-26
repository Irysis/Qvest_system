#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe_dart_segment.py — DART OpenAPI에서 '제품별/사업부문별 매출'이
API로 가능한가 vs 원문 파싱이 필요한가를 실측으로 가른다.

측정 대상 (전부 HTTP 실호출, 상태코드/본문 근거 기록):
  T1  company.json          — induty_code(KSIC) 확보 여부 (이미 crosswalk에 있음, 재확인)
  T2  fnlttSinglAcntAll     — 전체 재무제표에 부문/제품 라인아이템이 있는가
  T3  list.json             — 사업보고서 rcept_no 확보 가능한가
  T4  document.xml          — 원문 ZIP 취득 + '매출' 섹션 존재 여부
  T5  fnlttSinglIndx        — 주요 재무지표에 부문 정보 있는가

키는 .env DART_API_KEY 에서만 읽고 절대 출력하지 않는다.
"""
import os, re, sys, io, json, zipfile, time
import urllib.request, urllib.parse

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold/fq073")
os.makedirs(OUT, exist_ok=True)


def load_key(name="DART_API_KEY"):
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8", errors="ignore") as f:
        for ln in f:
            ln = ln.strip()
            if ln.startswith(name + "="):
                return ln.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("[probe] %s 부재" % name)


KEY = load_key()
MASK = lambda s: s.replace(KEY, "<KEY>") if KEY else s


def get(url, params, binary=False, timeout=60):
    q = urllib.parse.urlencode(params)
    full = url + "?" + q
    req = urllib.request.Request(full, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            return r.status, (body if binary else body.decode("utf-8", "replace")), MASK(full)
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:400].decode("utf-8", "replace"), MASK(full)
    except Exception as e:
        return -1, "EXC:%s" % e, MASK(full)


BASE = "https://opendart.fss.or.kr/api/"
# 삼성전자 00126380 / SK하이닉스 00164779 / 현대차 00164742 / POSCO홀딩스 00155319
SAMPLES = [("00126380", "삼성전자"), ("00164779", "SK하이닉스"), ("00164742", "현대차")]

report = {"probes": []}


def rec(name, status, note, sample=None):
    report["probes"].append({"probe": name, "http": status, "note": note, "sample": sample})
    print("[%s] http=%s %s" % (name, status, note))


# ── T2. 단일회사 전체 재무제표 — 부문/제품 라인아이템 존재 여부 ──────────────
st, body, u = get(BASE + "fnlttSinglAcntAll.json", dict(
    crtfc_key=KEY, corp_code="00126380", bsns_year="2024", reprt_code="11011", fs_div="CFS"))
try:
    j = json.loads(body)
    lst = j.get("list", [])
    accs = sorted({x.get("account_nm", "") for x in lst})
    hits = [a for a in accs if any(k in a for k in ("부문", "제품", "세그먼트", "지역"))]
    rec("T2_fnlttSinglAcntAll", st,
        "status=%s n_line=%d distinct_account=%d  부문/제품 키워드 라인=%d" %
        (j.get("status"), len(lst), len(accs), len(hits)),
        {"keyword_hits": hits[:20], "first_accounts": accs[:15]})
except Exception as e:
    rec("T2_fnlttSinglAcntAll", st, "parse_fail %s :: %s" % (e, body[:200]))

# ── T5. 단일회사 주요 재무지표 ───────────────────────────────────────────────
st, body, u = get(BASE + "fnlttSinglIndx.json", dict(
    crtfc_key=KEY, corp_code="00126380", bsns_year="2024", reprt_code="11011", idx_cl_code="M210000"))
try:
    j = json.loads(body)
    lst = j.get("list", [])
    rec("T5_fnlttSinglIndx", st, "status=%s n=%d" % (j.get("status"), len(lst)),
        {"idx_nm": sorted({x.get("idx_nm", "") for x in lst})[:20]})
except Exception as e:
    rec("T5_fnlttSinglIndx", st, "parse_fail %s :: %s" % (e, body[:200]))

# ── T3. 사업보고서 목록 (list.json) ─────────────────────────────────────────
rcept = {}
for cc, nm in SAMPLES:
    st, body, u = get(BASE + "list.json", dict(
        crtfc_key=KEY, corp_code=cc, bgn_de="20240101", end_de="20250630",
        pblntf_ty="A", page_count="100"))
    try:
        j = json.loads(body)
        lst = j.get("list", []) or []
        biz = [x for x in lst if "사업보고서" in x.get("report_nm", "")]
        if biz:
            rcept[cc] = biz[0]["rcept_no"]
        rec("T3_list_%s" % nm, st, "status=%s n=%d 사업보고서=%d rcept=%s" %
            (j.get("status"), len(lst), len(biz), biz[0]["rcept_no"] if biz else "-"),
            {"report_nms": [x.get("report_nm") for x in lst[:6]]})
    except Exception as e:
        rec("T3_list_%s" % nm, st, "parse_fail %s :: %s" % (e, body[:200]))
    time.sleep(0.2)

# ── T4. document.xml 원문 ZIP → '매출' 섹션 탐색 ─────────────────────────────
for cc, nm in SAMPLES:
    rn = rcept.get(cc)
    if not rn:
        rec("T4_doc_%s" % nm, "skip", "rcept_no 없음")
        continue
    st, body, u = get(BASE + "document.xml", dict(crtfc_key=KEY, rcept_no=rn), binary=True, timeout=180)
    if st != 200 or not isinstance(body, (bytes, bytearray)):
        rec("T4_doc_%s" % nm, st, "non-200 or non-binary :: %s" % str(body)[:200])
        continue
    try:
        zf = zipfile.ZipFile(io.BytesIO(body))
        names = zf.namelist()
        sizes = {n: zf.getinfo(n).file_size for n in names}
        # 가장 큰 XML = 본문
        main = max(names, key=lambda n: sizes[n])
        raw = zf.read(main)
        # DART 원문은 EUC-KR/UTF-8 혼재
        txt = None
        for enc in ("utf-8", "cp949", "euc-kr"):
            try:
                txt = raw.decode(enc); break
            except Exception:
                continue
        txt = txt or raw.decode("utf-8", "replace")
        plain = re.sub(r"<[^>]+>", " ", txt)
        plain = re.sub(r"\s+", " ", plain)
        kw = {k: plain.count(k) for k in ("매출 및 수주상황", "주요 제품", "매출실적", "품목", "생산능력", "사업의 내용")}
        # 매출실적 표 근처 스니펫
        m = re.search(r"(매출실적|매출 및 수주상황)", plain)
        snip = plain[m.start():m.start() + 700] if m else None
        os.makedirs(os.path.join(OUT, "raw_docs"), exist_ok=True)
        with open(os.path.join(OUT, "raw_docs", "%s_%s.xml" % (nm, rn)), "wb") as f:
            f.write(raw)
        rec("T4_doc_%s" % nm, st, "zip files=%d main=%s bytes=%d keyword=%s" %
            (len(names), main, len(raw), kw), {"snippet": snip})
    except Exception as e:
        rec("T4_doc_%s" % nm, st, "zip/parse fail %s (bytes=%d)" % (e, len(body)))
    time.sleep(0.5)

with open(os.path.join(OUT, "probe_dart_segment.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print("\n[probe] saved ->", os.path.join(OUT, "probe_dart_segment.json"))
