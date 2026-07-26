#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_fq073_crosswalk.py (v2) — HS코드 × 상장종목 crosswalk 구축 + 커버리지 실측.

v1 대비 수리 2건 (실사고 근거):
  (1) 한국어 substring 오탐 → lexmatch 경계 가드.  '참**고로**'가 HS7208(철강 열연)로
      매칭돼 네이버가 '철강'으로 배정됐던 버그. (동일 실패 모드가 본 저장소 하버스터
      `_infer_family`에서도 적발된 바 있음 — word-boundary 근본수리 2026-07-18)
  (2) 불완전 사전 argmax 편향 → nontrade_lexicon 도입.  HS 사전만으로 argmax하면
      비교역 매출이 지배적인 기업도 부수 재화 키워드 1개에 끌려간다. 실사고: 삼성물산
      (건설 40%+인데 바이오 10.8% 키워드가 argmax 승리). 비교역 어휘를 같은 경기장에
      넣어 경쟁시키면 정상 배제된다.

3축 독립 판정: KSIC(DART 공식 신고) · WICS Sector_Lv2(시장 분류) · 사업보고서 원문 텍스트.

입력:
  ../firm_crosswalk.parquet          474사 firm-identity
  dart_products/<Ticker>.json        DART 사업보고서 제품/매출 섹션 발췌
  ksic_hs_rules.json / hs_lexicon.json / nontrade_lexicon.json / wics_tradeable.json
  guards.json                        collision_scan 실측 근거의 경계 가드/차단 목록
  <ROOT>/.cache/rawdata.parquet      시총(Size) + WICS + K200/KQ150

출력: firm_hs_crosswalk.parquet(+csv) · hs_coverage.json · mapping_audit.json
"""
import os, re, json, unicodedata
import pandas as pd
import lexmatch

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCAF = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
FQ = os.path.join(SCAF, "fq073")

# ── 판정 임계 (감사 가능하도록 상수 노출) ─────────────────────────────────
TH_A = 6          # GOODS 등급 A가 되기 위한 최소 HS 텍스트 점수
TH_WEAK = 6       # 약한-텍스트 경로(B)의 점수 하한. 미달 시 KSIC 기본값 또는 C로 강등
TH_OVERRIDE = 14  # KSIC 章과 불일치해도 텍스트가 이기는 점수(자기신고 KSIC noisy)
TH_REROUTE = 14   # NONTRADE/HOLDCO KSIC를 텍스트로 뒤집는 최소 점수
MARGIN_NT = 1.25  # 텍스트가 '재화'로 판정되려면 비교역 점수 대비 이 배수 이상
MARGIN_REROUTE = 2.0
TH_SECONDARY = 0.40

lexmatch.load_guards(os.path.join(FQ, "guards.json"))
KRULE = {k: v for k, v in json.load(open(os.path.join(FQ, "ksic_hs_rules.json"), encoding="utf-8")).items()
         if not k.startswith("_")}
HS_LEX = json.load(open(os.path.join(FQ, "hs_lexicon.json"), encoding="utf-8"))
NT_LEX = json.load(open(os.path.join(FQ, "nontrade_lexicon.json"), encoding="utf-8"))
WICS = {k: v for k, v in json.load(open(os.path.join(FQ, "wics_tradeable.json"), encoding="utf-8")).items()
        if not k.startswith("_")}
HSC = lexmatch.build(HS_LEX)
NTC = lexmatch.build(NT_LEX)
DESC = {k: v["desc"] for k, v in HS_LEX.items() if not k.startswith("_")}


def ksic_lookup(code):
    c = str(code or "").strip()
    for L in (5, 4, 3, 2):
        if len(c) >= L and c[:L] in KRULE:
            return c[:L], KRULE[c[:L]]
    return None, {"class": "UNKNOWN", "chapters": [], "hs4": None, "label": "미분류"}


TOC = re.compile(r"-{3,}")


def clean_text(rec):
    parts = []
    for f in ("text_sales", "text_overview"):
        for seg in (rec.get(f) or "").split(" ||| "):
            if len(TOC.findall(seg)) >= 3:
                continue
            parts.append(seg)
    return unicodedata.normalize("NFKC", " ".join(parts))


# ── 명시적 매출 비중 표 파싱 (품목 + 금액 + 비율%) ────────────────────────
PCT_ROW = re.compile(r"([가-힣A-Za-z][가-힣A-Za-z0-9()·,/\s]{1,30}?)\s+([\d]{1,3}(?:,\d{3}){1,6})\s*\(?\s*(\d{1,3}(?:\.\d{1,2})?)\s*%")


def parse_shares(txt):
    rows = []
    for m in PCT_ROW.finditer(txt):
        try:
            amt, pct = float(m.group(2).replace(",", "")), float(m.group(3))
        except Exception:
            continue
        it = m.group(1).strip()
        if 0 < pct <= 100 and len(it) >= 2:
            rows.append({"item": it[:40], "amount": amt, "pct": pct})
    rows = rows[:12]
    tot = sum(r["pct"] for r in rows)
    return rows, (95.0 <= tot <= 105.0)


# ── 로드 ──────────────────────────────────────────────────────────────────
xw = pd.read_parquet(os.path.join(SCAF, "firm_crosswalk.parquet"))
raw = pd.read_parquet(ROOT + "/.cache/rawdata.parquet",
                      columns=["Date", "Ticker", "Size", "Sector", "Sector_Lv2", "K200", "KQ150", "Name"])
raw["Date"] = pd.to_datetime(raw["Date"])
last = raw[raw.Date == raw.Date.max()]
xw = xw.join(last.set_index("Ticker")[["Size", "Sector", "Sector_Lv2", "K200", "KQ150", "Name"]], on="Ticker")
xw["in_univ_now"] = (xw["K200"].fillna(0) > 0) | (xw["KQ150"].fillna(0) > 0)

recs, dump = [], {}
for _, r in xw.iterrows():
    tk = r["Ticker"]
    fp = os.path.join(FQ, "dart_products", "%s.json" % tk)
    doc = json.load(open(fp, encoding="utf-8")) if os.path.exists(fp) else {}
    txt = clean_text(doc)
    s_hs, hits_hs = lexmatch.score(txt, HSC, collect_hits=True)
    s_nt, hits_nt = lexmatch.score(txt, NTC, collect_hits=True)

    hs_rank = sorted(s_hs.items(), key=lambda x: -x[1])
    nt_rank = sorted(s_nt.items(), key=lambda x: -x[1])
    #  ★章-우선 집계: 같은 사업이 형제 HS4로 쪼개지면(선박 8901/8905/8906) 개별 argmax가
    #    소수 부업(태양광 8541)에 진다. 실사고: HD한국조선해양 → 8541 오배정
    #    (8901+8905+8906=90 > 8541=54인데도). 章 합계로 먼저 이기는 章을 고르고,
    #    그 章 안에서 HS4를 고른다.
    chap_sc = {}
    for h, v in s_hs.items():
        chap_sc[h[:2]] = chap_sc.get(h[:2], 0) + v
    chap_rank = sorted(chap_sc.items(), key=lambda x: -x[1])

    kkey0, krule0 = ksic_lookup(r["induty_code"])
    kchaps0 = krule0["chapters"]
    #  KSIC-prior: 텍스트 상위 章 중 KSIC가 허용하는 章이 있으면 그것을 택한다.
    #  근거(실측): 한화에어로는 章 합계로만 뽑으면 85(방산전자·영상 잡음 합계 128)가
    #  93(탄약·미사일 90)을 이겨 오배정. KSIC 31321이 허용하는 [88,93,84] 중 최고인
    #  93을 택하면 정상. 반대로 KSIC가 章을 안 주는 지주/미상 기업은 텍스트 최고 章.
    pick, rule = (None, "none")
    if chap_rank:
        allowed = [(c, v) for c, v in chap_rank if c in kchaps0]
        if allowed:
            pick, rule = allowed[0][0], "ksic_allowed_chapter"
        else:
            pick, rule = chap_rank[0][0], "text_top_chapter"
    best_chap = pick
    in_chap = [(h, v) for h, v in hs_rank if best_chap and h[:2] == best_chap]
    t_hs, v_hs_top = (in_chap[0] if in_chap else (None, 0))
    v_hs = chap_sc.get(best_chap, 0)                 # 판정에는 선택된 章의 합계 점수
    t_hs2, v_hs2 = next(((h, v) for h, v in hs_rank if h != t_hs), (None, 0))
    t_nt, v_nt = (nt_rank[0] if nt_rank else (None, 0))
    hs_total = sum(s_hs.values())
    chap_share = round(v_hs / hs_total, 3) if hs_total else 0.0
    hs4_share = round(v_hs_top / hs_total, 3) if hs_total else 0.0
    dump[tk] = {"hs": hs_rank[:6], "chapters": chap_rank[:4], "nt": nt_rank[:4],
                "hs_kw": {k: hits_hs.get(k, {}) for k, _ in hs_rank[:3]},
                "nt_kw": {k: hits_nt.get(k, {}) for k, _ in nt_rank[:2]}}

    if v_hs >= TH_A and v_hs >= MARGIN_NT * v_nt:
        tverdict = "GOODS"
    elif v_nt > v_hs:
        tverdict = "NONTRADE"
    else:
        tverdict = "WEAK"

    kkey, krule = ksic_lookup(r["induty_code"])
    kclass, kchaps, khs4 = krule["class"], krule["chapters"], krule["hs4"]
    wclass = WICS.get(r.get("Sector_Lv2"), "UNKNOWN")
    chap_ok = bool(t_hs) and (not kchaps or t_hs[:2] in kchaps)

    hs4 = grade = basis = None
    conflict = False
    if kclass == "GOODS":
        if wclass == "NONTRADE" and tverdict == "NONTRADE":
            hs4, grade, basis, conflict = None, "X", "ksic_goods_but_wics+text_nontrade", True
        elif tverdict == "GOODS" and chap_ok:
            hs4, grade, basis = t_hs, "A", "text+ksic_agree"
        elif tverdict == "GOODS" and v_hs >= TH_OVERRIDE:
            hs4, grade, basis, conflict = t_hs, "A", "text_override_ksic_chapter", True
        elif khs4:
            hs4, grade, basis = khs4, "B", "ksic_default_hs4"
        elif tverdict == "GOODS":
            hs4, grade, basis = t_hs, "B", "text_only_chapter_mismatch"
        elif t_hs and v_hs >= TH_WEAK and chap_ok:
            #  ★하한(TH_WEAK) 필수: 하한이 없으면 우연한 1회 매치가 통과한다.
            #  실사고: 천보(2차전지 전해질 첨가제)가 '타이어' 1회 매치(점수 3)로 HS4011 배정.
            hs4, grade, basis = t_hs, "B", "text_weak_but_ksic_chapter_ok"
        else:
            hs4, grade, basis = None, "C", "ksic_chapter_only"
    elif kclass == "HOLDCO":
        if tverdict == "GOODS" and v_hs >= TH_REROUTE and v_hs >= MARGIN_REROUTE * v_nt:
            hs4, grade, basis = t_hs, "B", "holdco_text_reroute"
        else:
            hs4, grade, basis = None, "X", "holdco_financial_or_mixed"
    elif kclass == "TRADER":
        hs4, grade, basis = None, "T", "trader_intermediary"
    elif kclass in ("NONTRADE", "RND"):
        if (tverdict == "GOODS" and v_hs >= TH_REROUTE and v_hs >= MARGIN_REROUTE * v_nt
                and wclass != "NONTRADE"):
            hs4, grade, basis, conflict = t_hs, "B", "nontrade_ksic_text_reroute", True
        else:
            hs4, grade, basis = None, "X", ("rnd_clinical_stage" if kclass == "RND" else "nontradeable_sector")
    else:
        if tverdict == "GOODS" and v_hs >= TH_OVERRIDE:
            hs4, grade, basis = t_hs, "B", "ksic_unknown_text_only"
        else:
            hs4, grade, basis = None, "C", "ksic_unknown"

    sec = t_hs2 if (t_hs2 and v_hs and v_hs2 >= TH_SECONDARY * v_hs and grade in ("A", "B")) else None
    chap = hs4[:2] if hs4 else (kchaps[0] if kchaps else None)
    shares, share_ok = parse_shares(doc.get("text_sales") or "")
    votes_g = int(kclass == "GOODS") + int(wclass == "GOODS") + int(tverdict == "GOODS")

    recs.append(dict(
        Ticker=tk, corp_name=r["corp_name"], stock_code=r["stock_code"], corp_code=r["corp_code"],
        bizr_no=r["bizr_no"], induty_code=r["induty_code"], ksic_rule=kkey,
        ksic_label=krule["label"], ksic_class=kclass,
        wics_sector=r.get("Sector"), wics_sector_lv2=r.get("Sector_Lv2"), wics_class=wclass,
        text_verdict=tverdict, mktcap_krw_mn=r.get("Size"), in_univ_now=bool(r["in_univ_now"]),
        hs4=hs4, hs_chapter=chap, hs4_desc=(DESC.get(hs4) if hs4 else None),
        hs4_secondary=sec, hs4_secondary_desc=(DESC.get(sec) if sec else None),
        confidence=grade, basis=basis, axes_voting_goods=votes_g, ksic_text_conflict=conflict,
        text_best_chapter=best_chap, text_chapter_score=int(v_hs),
        text_chapter_share=chap_share, text_top_hs4_score=int(v_hs_top),
        chapter_pick_rule=rule, hs4_score_share=hs4_share,
        multi_hs=bool(hs_total and hs4_share < 0.50),
        hs_chapters_top3=json.dumps(chap_rank[:3], ensure_ascii=False),
        text_top_hs=t_hs, text_top_score=int(v_hs), text_runnerup_hs=t_hs2,
        text_runnerup_score=int(v_hs2), text_top_nontrade=t_nt, text_nontrade_score=int(v_nt),
        text_len=len(txt), dart_rcept_no=doc.get("rcept_no"), dart_rcept_dt=doc.get("rcept_dt"),
        dart_status=doc.get("status"), n_explicit_share_rows=len(shares),
        explicit_shares_sum_ok=bool(share_ok),
        explicit_shares=json.dumps(shares, ensure_ascii=False) if shares else None))

df = pd.DataFrame(recs)
tot_n, tot_cap = len(df), df["mktcap_krw_mn"].fillna(0).sum()


def blk(m):
    return dict(n=int(m.sum()), pct_of_474=round(100 * m.sum() / tot_n, 2),
                mktcap_share_pct=round(100 * df.loc[m, "mktcap_krw_mn"].fillna(0).sum() / tot_cap, 2))


mA, mB, mC = df.confidence == "A", df.confidence == "B", df.confidence == "C"
mT, mX = df.confidence == "T", df.confidence == "X"
mMap, mPool = df.hs4.notna(), df.confidence.isin(["A", "B", "C"])
pool_cap = df.loc[mPool, "mktcap_krw_mn"].fillna(0).sum()

cov = {
    "built_at": pd.Timestamp.now().isoformat(timespec="seconds"),
    "universe": {
        "definition": "firm_crosswalk.parquet — universe_monthly union(univ==TRUE, ym>=2023-01) = K200∪KQ150",
        "n_firms": tot_n, "n_in_univ_on_last_date": int(df.in_univ_now.sum()),
        "mktcap_asof": str(raw.Date.max().date()), "mktcap_total_krw_mn": float(tot_cap)},
    "dart_pull": {
        "n_with_report_text": int((df.text_len > 0).sum()),
        "n_zero_text": int((df.text_len == 0).sum()),
        "median_text_len": int(df.text_len.median()),
        "n_dart_status_ok": int(df.dart_status.isin(["ok", "ok_retry"]).sum())},
    "coverage_by_confidence": {
        "A_text_and_ksic_agree": blk(mA), "B_single_source_or_reroute": blk(mB),
        "C_chapter_only_unresolved": blk(mC), "T_trader_not_manufacturer": blk(mT),
        "X_excluded_nontradeable": blk(mX)},
    "headline": {
        "hs4_assigned_any": blk(mMap),
        "hs4_reliable_A_or_B": blk(mA | mB),
        "goods_pool_ABC": blk(mPool),
        "reliable_pct_of_goods_pool": round(100 * (mA | mB).sum() / max(int(mPool.sum()), 1), 2),
        "reliable_mktcap_pct_of_goods_pool": round(
            100 * df.loc[mA | mB, "mktcap_krw_mn"].fillna(0).sum() / max(pool_cap, 1e-9), 2)},
    "hs4_vs_chapter_reliability": {
        "note": "章(2자리)은 신뢰 단위, HS4는 best-effort. 다제품 기업은 단일 HS4가 원리상 부정확 — "
                "hs4_score_share<0.5면 multi_hs 플래그(가중 소비 권장, 단일 HS4 사용 금지).",
        "n_multi_hs_flagged": int(df.multi_hs.sum()),
        "multi_hs_mktcap_pct": round(100 * df.loc[df.multi_hs, "mktcap_krw_mn"].fillna(0).sum() / tot_cap, 2),
        "median_hs4_score_share_mapped": float(df.loc[mMap, "hs4_score_share"].median()),
        "median_chapter_share_mapped": float(df.loc[mMap, "text_chapter_share"].median()),
        "chapter_pick_rule_counts": df.loc[mMap, "chapter_pick_rule"].value_counts().to_dict()},
    "axes_agreement": {
        "n_3of3_goods": int((df.axes_voting_goods == 3).sum()),
        "n_2of3_goods": int((df.axes_voting_goods == 2).sum()),
        "n_1of3_goods": int((df.axes_voting_goods == 1).sum()),
        "n_0of3_goods": int((df.axes_voting_goods == 0).sum()),
        "mktcap_pct_3of3": round(100 * df.loc[df.axes_voting_goods == 3, "mktcap_krw_mn"].fillna(0).sum() / tot_cap, 2)},
    "explicit_revenue_share_parse": {
        "n_firms_any_row": int((df.n_explicit_share_rows > 0).sum()),
        "n_firms_sum_95_105": int(df.explicit_shares_sum_ok.sum()),
        "pct_of_474_validated": round(100 * df.explicit_shares_sum_ok.sum() / tot_n, 2),
        "note": "'품목 금액 비율%' 정규식 추출. 합계 95~105%인 경우만 validated로 셈. "
                "필러별 표 서식이 제각각이라 미검증분은 품목명 절단·비율 오추출 가능. "
                "★본 crosswalk의 HS 가중치 산출에는 사용하지 않았다(진단 지표)."},
    "hs_chapter_distribution": (df[mMap].groupby(df.hs4.str[:2]).agg(
        n=("Ticker", "size"),
        mktcap_share_pct=("mktcap_krw_mn", lambda s: round(100 * s.fillna(0).sum() / tot_cap, 2))
    ).sort_values("mktcap_share_pct", ascending=False).to_dict("index")),
    "top_hs4_by_mktcap": (df[mMap].groupby(["hs4", "hs4_desc"]).agg(
        n=("Ticker", "size"),
        mktcap_share_pct=("mktcap_krw_mn", lambda s: round(100 * s.fillna(0).sum() / tot_cap, 2))
    ).sort_values("mktcap_share_pct", ascending=False).head(25).reset_index().to_dict("records")),
    "excluded_breakdown": (df[mX | mT].groupby(["confidence", "basis"]).agg(
        n=("Ticker", "size"),
        mktcap_share_pct=("mktcap_krw_mn", lambda s: round(100 * s.fillna(0).sum() / tot_cap, 2))
    ).reset_index().to_dict("records")),
    "thresholds": {"TH_A": TH_A, "TH_WEAK": TH_WEAK, "TH_OVERRIDE": TH_OVERRIDE, "TH_REROUTE": TH_REROUTE,
                   "MARGIN_NT": MARGIN_NT, "MARGIN_REROUTE": MARGIN_REROUTE,
                   "TH_SECONDARY": TH_SECONDARY},
}

df.to_parquet(os.path.join(FQ, "firm_hs_crosswalk.parquet"), index=False)
df.to_csv(os.path.join(FQ, "firm_hs_crosswalk.csv"), index=False, encoding="utf-8-sig")
json.dump(cov, open(os.path.join(FQ, "hs_coverage.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, default=str)

cols = ["Ticker", "corp_name", "induty_code", "ksic_label", "wics_sector_lv2", "hs4",
        "hs4_desc", "hs4_secondary", "confidence", "basis", "text_top_score", "text_nontrade_score"]
audit = {
    "ksic_rule_evidence": {},
    "top30_mktcap_mapping": df.sort_values("mktcap_krw_mn", ascending=False)[cols].head(30).to_dict("records"),
    "conflicts_flagged": df[df.ksic_text_conflict].sort_values("mktcap_krw_mn", ascending=False)[cols].to_dict("records"),
    "grade_C_unresolved": df[mC].sort_values("mktcap_krw_mn", ascending=False)[cols].to_dict("records"),
    "grade_B_reroutes": df[mB & df.basis.str.contains("reroute")].sort_values(
        "mktcap_krw_mn", ascending=False)[cols].to_dict("records"),
    "excluded_largest": df[mX].sort_values("mktcap_krw_mn", ascending=False)[cols].head(40).to_dict("records"),
    "traders": df[mT].sort_values("mktcap_krw_mn", ascending=False)[cols].to_dict("records"),
    "text_score_dump": dump,
}
for key in sorted(set(df.ksic_rule.dropna())):
    sub = df[df.ksic_rule == key]
    audit["ksic_rule_evidence"][key] = {
        "label": KRULE[key]["label"], "class": KRULE[key]["class"], "n": len(sub),
        "firms": sub.corp_name.head(6).tolist(), "assigned_hs4": sub.hs4.value_counts().head(4).to_dict()}
json.dump(audit, open(os.path.join(FQ, "mapping_audit.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, default=str)

print(json.dumps({k: cov[k] for k in ("coverage_by_confidence", "headline", "axes_agreement",
                                      "explicit_revenue_share_parse")}, ensure_ascii=False, indent=2))
print("\n[chapters]")
for c, v in list(cov["hs_chapter_distribution"].items())[:16]:
    print("  HS%s n=%-4s cap%%=%s" % (c, v["n"], v["mktcap_share_pct"]))
print("\n[saved]", FQ)
