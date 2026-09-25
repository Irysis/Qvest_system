# 규칙 파일 b1 → b2: ALFRED 빈티지 목록 대조로 반증된 고정 상한을 보강한다(판정서 ② 정정).
# 입력: 원 규칙 파일(인자1), design.json(같은 폴더), 출력 경로(인자2). 운영 파일에 직접 쓰지 않는다.
import json, sys, io
src, dst = sys.argv[1], sys.argv[2]
R = json.load(io.open(src, encoding="utf-8"))
D = json.load(io.open("design.json", encoding="utf-8"))
ALF = "https://alfred.stlouisfed.org/series/downloaddata?seid={sid} 의 빈티지 날짜 목록(2026-09-24 열람)"
CHECK = ("04_Research/01_reports/pit_c11_20260924/evidence/r1_alfred/check_bounds.R·design.R — 창(기간 끝, 다음 기간 끝] 안 마지막 빈티지 R*"
         "(개정 전용 빈티지가 공표 앞에 끼면 첫 빈티지가 공표보다 이르다 → 늦은 쪽을 쓴다 · 창이 비면 기간 끝 뒤 첫 빈티지)")
by = {s["id"]: s for s in R["series"]}

def add_bound(sid, bound):
    by[sid]["bounds"].append(bound)

def add_overrides(sid, rows, why):
    ov = by[sid].setdefault("release_overrides", [])
    have = {o["obs"]: o for o in ov}
    for r in rows:
        o = r["obs"]
        if o in have:
            # 기존 override(셧다운 공표일)는 유지하되 ALFRED 가 더 늦으면 늦은 쪽으로
            if r["us_release"] > have[o]["us_release"]:
                have[o]["source"] += f" · ALFRED R* {r['us_release']} 가 더 늦어 교체(원 {have[o]['us_release']})"
                have[o]["us_release"] = r["us_release"]
            continue
        ov.append({"obs": o, "us_release": r["us_release"],
                   "source": f"{r.get('note', why)} — ALFRED 기간 끝 뒤 첫 빈티지 {r['first_vintage']} · 창 안 빈티지 {r['nwin']}개 · R* {r['us_release']}(보수). {ALF.format(sid=sid)}"})
    ov.sort(key=lambda x: x["obs"])

def ovr(sid):
    return D[sid]["overrides"]

def bd_bound(sid, month_offset, n, extra=""):
    d = D[sid]
    return {"type": "us_release",
            "release": {"kind": "month_nth_us_business_day", "month_offset": month_offset, "n": n},
            "us_holiday_roll": False, "kr_rule": "strictly_after",
            "basis": (f"r1 보강(2026-09-24 · 판정서 ② 정정): ALFRED 빈티지 대조 {d['first']}~{d['last']} {d['n_obs']}관측 중 "
                      f"창 안 빈티지가 하나뿐인(공표가 모호하지 않은) {d.get('n_unamb','?')}관측의 R* 최대 = M+{month_offset}월 {n}번째 미국 영업일"
                      f"(셧다운 관측 제외). 그보다 늦은 관측은 release_overrides. 공표 시각(미국 오전 ET)은 한국 15:30 이후 → 다음 한국 거래일. {extra}"
                      f"근거: {ALF.format(sid=sid)} · {CHECK}")}

# ── CPIAUCSL: +48 은 상한이 아니다(V2: BLS 실공표 5건 · ALFRED 46관측 위반) ─────────────
add_bound("CPIAUCSL", bd_bound("CPIAUCSL", 1, D["CPIAUCSL"]["n"],
          "BLS 실공표 대조(V2): 2003-01→02-21·2004-12→2005-01-19·2005-01→02-23·2010-01→02-19·2015-12→2016-01-20 모두 이 상한 안. "))
add_overrides("CPIAUCSL", ovr("CPIAUCSL"), "r1 보강")
# ── INDPRO: 셧다운 지연(V1: 2025-09분 11-24 · 2025-10분 12-03) ────────────────────
add_bound("INDPRO", bd_bound("INDPRO", 1, D["INDPRO"]["n"]))
ind = [dict(r) for r in ovr("INDPRO")]
for r in ind:
    if r["obs"] == "2025-10-01":
        r["us_release"] = "2025-12-03"   # V1: 11-24 판은 9월분, 10월분은 공표 순서상 12-03 판(보수 = 늦은 쪽)
        r["note"] = "r1 보강(V1 소견: 11-24 판은 9월분, 10월분은 공표 순서상 12-03 판 — 늦은 쪽)"
add_overrides("INDPRO", ind, "r1 보강")
# ── PERMIT: 셧다운(2013·2018-19·2025) · 창에 빈티지 2개가 보통(NRC 공표 + 개정) ──────────
add_bound("PERMIT", bd_bound("PERMIT", 1, D["PERMIT"]["n"], "창 안 빈티지가 보통 2개라(예비·개정) 늦은 쪽 기준 — 보수. "))
add_overrides("PERMIT", ovr("PERMIT"), "r1 보강")
# ── FEDFUNDS: FRED 게시가 M+1월 셋째 한국 영업일보다 늦은 달이 있다 ─────────────────
add_bound("FEDFUNDS", bd_bound("FEDFUNDS", 1, D["FEDFUNDS"]["n"]))
add_overrides("FEDFUNDS", ovr("FEDFUNDS"), "r1 보강")
# ── PCOPPUSDM: IMF 게시 공백(2016·2019·2022·2025) ──────────────────────────────
add_bound("PCOPPUSDM", bd_bound("PCOPPUSDM", 1, D["PCOPPUSDM"]["n"]))
add_overrides("PCOPPUSDM", ovr("PCOPPUSDM"), "r1 보강(IMF 게시 공백)")
# ── DRTSCILM: 라벨 +37 은 전 관측 위반 — FRED 라벨 분기 첫날, 게시는 넷째 달 ─────────────
add_bound("DRTSCILM", bd_bound("DRTSCILM", 4, D["DRTSCILM"]["n"], "라벨(분기 첫날)의 +37일은 ALFRED 대조 65/65 위반이었다. "))
# ── NFCI: 월요일 미국 휴일 주는 목요일 공표(라벨 +6 = 한국 목요일 15:30 < 미국 목 08:30 ET) ──
d = D["NFCI"]
add_bound("NFCI", {"type": "us_release", "release": {"kind": "us_business_days_after", "n": d["n"]},
                   "us_holiday_roll": False, "kr_rule": "strictly_after",
                   "basis": (f"r1 보강: ALFRED 대조 {d['first']}~{d['last']} {d['n_obs']}주 — 공표 = 라벨(금) 이후 {d['n']}번째 미국 영업일"
                             f"(월요일 휴일 주는 목요일). 라벨 +6(한국 목)은 휴일 주 104건에서 공표 당일(미국 오전 = 한국 밤)이라 위반이었다. "
                             f"근거: {ALF.format(sid='NFCI')} · {CHECK}")})
add_overrides("NFCI", ovr("NFCI"), "r1 보강")
# ── ICSA·WALCL: 규칙은 유지, 지연 공표 주만 override ─────────────────────────────
add_overrides("ICSA", ovr("ICSA"), "r1 보강(2025 셧다운 주간 공표 중단 → 11-20 일괄 · 기타 지연 주)")
add_overrides("WALCL", ovr("WALCL"), "r1 보강")

GAP_NOTE = {("ICSA", "2018-03-17"): "주의: 03-22 빈티지 부재 — ALFRED 공백 의심(실공표는 03-22 였을 가능성). 보수로 유지",
            ("WALCL", "2018-01-03"): "주의: 01-04 빈티지 부재 — ALFRED 공백 의심. 보수로 유지"}
for (sid, ob), note in GAP_NOTE.items():
    for o in by[sid].get("release_overrides") or []:
        if o["obs"] == ob:
            o["source"] = note + " · " + o["source"]
for sid, gap in (("ICSA", "2025-10 셧다운 기간 주간 공표 일정 — r1 에서 ALFRED 빈티지 목록으로 확인해 override(2025-09-27~11-08분 = 11-20)"),
                 ("PERMIT", "셧다운 기간 공표 지연 — r1 에서 ALFRED 빈티지 목록으로 확인해 override")):
    by[sid]["known_gaps"] = [gap]
for sid in ("CPIAUCSL", "INDPRO", "PERMIT", "FEDFUNDS", "PCOPPUSDM", "DRTSCILM", "NFCI", "ICSA", "WALCL"):
    vr = by[sid].setdefault("verdict_rows", [])
    if "r1_alfred_check" not in vr:
        vr.append("r1_alfred_check")

R["version"] = "2026-09-24.b2"
R["history_verified"] = "partial"
R["history_check"] = {
    "date": "2026-09-24",
    "method": ("ALFRED 빈티지 날짜 목록(공개 페이지)과 .cache/macro_fred.parquet 관측일을 맞대어, 관측마다 보수 공표일 R* 를 잡고 "
               "규칙 가용일(한국)이 R* 보다 엄격히 늦은지 전수 대조. 값(빈티지)은 여전히 최신판 — 안 C 몫."),
    "evidence": ["04_Research/01_reports/pit_c11_20260924/evidence/r1_alfred/check_bounds.R (b1 위반 수 · b2 위반 0 재현)",
                 "04_Research/01_reports/pit_c11_20260924/evidence/r1_alfred/design.R · design.json (상한 n · override 산출)",
                 "04_Research/01_reports/pit_c11_20260924/evidence/r1_alfred/vint_<ID>.txt (열람한 빈티지 목록 사본)"],
    "b1_violations_first_vintage_vs_Rstar": {"CPIAUCSL": [46, 52], "INDPRO": [3, 14], "PERMIT": [8, 222], "FEDFUNDS": [89, 93],
                      "PCOPPUSDM": [38, 38], "DRTSCILM": [65, 65], "NFCI": [108, 108], "ICSA": [8, 9], "WALCL": [2, 2],
                      "UNRATE": [0, 0], "M2SL": [0, 0], "UMCSENT": [0, 0], "STLFSI4": [0, 0]},
    "b2_violations": "0 (전 계열 · 첫 빈티지·R* 두 기준 모두)",
    "coverage": {sid: f"{D[sid]['first']}~{D[sid]['last']} ({D[sid]['n_obs']}관측)" for sid in D},
    "not_covered": ("ALFRED 빈티지가 없는 기간(예: NFCI 2011-05 이전 · ICSA 2009-05 이전 · WALCL 2011-07 이전 · STLFSI4 2022-11 이전 · "
                    "PCOPPUSDM 2015-11 이전 · DRTSCILM 2010-04 이전)과 캐시 밖(2000 이전 관측)은 고정 규칙만 — 미검증. "
                    "일간 계열(VIX·DGS·ICE 등)은 이 대조 대상이 아니다(ALFRED 빈티지 없음)."),
}
R["residual_risk"] = [
    "주간·월간 고정 상한은 r1 에서 ALFRED 빈티지 목록으로 대조한 구간(history_check.coverage)에서만 상한임이 확인됐다. 그 밖(대조 불가 기간)은 미검증.",
    "R* 는 빈티지 '날짜'만으로 잡은 보수 추정이다(창 안 마지막 빈티지). 빈티지별 값 대조(안 C)가 아니므로 개정 전용 빈티지를 공표로 셀 수 있다 — 방향은 늦은 쪽(보수).",
    "빈티지는 최신판 — revisions != none_known 계열은 C1·C11 미해소 라벨.",
]
out = json.dumps(R, ensure_ascii=False, indent=2) + "\n"
io.open(dst, "w", encoding="utf-8", newline="\n").write(out)
print("wrote", dst, len(out))
