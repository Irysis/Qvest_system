setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")

## ── 1) close_round (capability_established — 무결성 근원수리) ──────────────────
source("02_Infrastructure/contracts/close_round.R")
rec <- close_round(
  round_id = "R47 (WT-D20260715_016, R46 P1 KRX 백필)",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "R46 tripwire가 특정한 218 source-seam Close 구멍(216 April-cluster 04-30~07-01 + 2 April-seam·전량 비-유니버스)을 KRX 일별 재수집으로 근원수리. ",
    "APPEND-ONLY(fill_set inner-join·collision 0)로 8,856행 채움(216종목·41일, KRX 캐시 56일+live 8일) → recompute==stored parity 회복(216/216 07-02 match)·source-seam 218→2. ",
    "가드 5종+parity 4종 전부 PASS: 기존 14,009,624행 max|ΔRet|=0·유니버스 행 2,370,544 불변·북 14보유 불변. 정지-재개 2행은 firewall NA(Close 참값 보존)."),
  next_probes = c(
    "잔여 2 penny(A150840·A208340, 03-30~04-29 KRX 미거래=Close 부재) 대체소스 재시도 — Naver 일별/월간 시세 또는 상장상태(실질 거래정지·관리종목) 재확인. 데이터 부재로 미충족이지 표적 회피 아님.",
    "tripwire 게이트화(R46 P2 이월): close_continuity_tripwire를 daily_refresh/factor_db 리빌드 pre-hook으로 승격 — 유니버스內 활성 구멍 발생 시 hard-block(April-gap 실데이터 삭제 사고류 사전차단).",
    "QuantiWise 재수출 자동 승격 확인: 다음 qw_refresh가 이 218 종목 05~06월을 수정주가로 자동 교체(incremental_ohlcvs)하는지 검증 — KRX 무수정주가 → QW 수정주가 승격 경로 정합."),
  consumer_surfaces = c(
    "①재료/데이터 원천: 218 non-universe seam Close 구멍 채움 = rawdata 완전성 회복(tripwire source-seam 218→2·total 245→29). recompute==stored parity 회복으로 밤샘 무결성 라인 R42~R47 근원수리 완결.",
    "⑧위험모델/감시: tripwire가 리빌드 전 이 구멍류를 재감지하는 pre-hook 게이트 후보(gate_flag_in_universe_active). 백필 후 gate clean 재확인.",
    "⑨자본/운영: 유니버스 행·현 북 14보유 parity 불변(max|ΔRet|=0) = 라이브 factor·recon NAV 무영향 재확인. book_state/05_Production 무변경."),
  frontier_update = "R46 P1(KRX 백필 리빌드) 소비 완료 — 218 source-seam Close 구멍 근원수리(잔여 2 penny=illiquidity 데이터 부재). 밤샘 무결성 라인 R42(적발)→R43(census)→R44(firewall)→R45(근원)→R46(정련·tripwire)→R47(KRX 백필 근원수리) 완결.",
  layer = "①재료(데이터 무결성 위생) — 성과 병목 아님. R46 P1 소비로 seam 근원(Close hole) 실수리. append-only 리빌드로 4월-사고(full-rebuild 삭제) 재발 원천차단.",
  evidence_refs = c(
    "verdict: stage_artifacts/WT_D20260715_016/verdict.json",
    "challenge: stage_artifacts/WT_D20260715_016/challenge_note.md",
    "diagnose: stage_artifacts/WT_D20260715_016/r47_diagnose.json",
    "merge+guards: stage_artifacts/WT_D20260715_016/r47_merge_guards.json",
    "parity: stage_artifacts/WT_D20260715_016/r47_parity_verify.json",
    "chart: stage_artifacts/WT_D20260715_016/r47_chart_integrity.png",
    "backup: .cache/rawdata_pre_r47_backup_20260715.parquet",
    "parent R46: stage_artifacts/WT_D20260715_015/verdict.json (P1 KRX 백필 armed)",
    "precedent: project-rawdata-april-gap-incident-20260711 (KRX 백필·가드 5종 재사용)"))
cat("\n[close_r47] marker 발행. verdict_type=", rec$verdict_type, "\n", sep="")

## ── 2) L-code emit (process·근원수리 — R44/R45/R46 선례 정합) ────────────────
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R47_krx_backfill_close_holes_parity_recovered",
  grade = "B",
  metric_type = "canonical_screen",
  record_type = "process",
  construction_type = "KRX 일별 OHLCV 재수집(캐시56+live8일) → fill_set inner-join APPEND-ONLY interior merge(temp-rename) → 가드5종+parity4종",
  selection_type = "chain",
  lesson_text = paste0(
"[데이터무결성 근원수리] R47 R46-P1 — R46 tripwire가 특정한 218 source-seam Close 구멍을 KRX 백필로 실수리. ★rawdata 실변경 유일 작업(밤샘 라인 중). append-only·KRX API만·단일스레드·io(2)·temp-rename·book/05_Production 무변경. ",
"★표적: 216 April-cluster(prevDate 04-29→Date 07-02, 결측 04-30~07-01) + 2 April-seam(A150840/A208340) = 전량 유니버스內 0. 근본: 이 218은 KRX 소스(04-29 backfill·07-02+ krx_api)에만 존재, 05~06월 QuantiWise-only 창에서 QW 미수출 → interior hole(유니버스 종목은 QW 완전커버라 유니버스內 0). ",
"★방법: KRX 일별 캐시 56/64일 재사용 + 8일(06-18/19/23/24/25/26/29/30) live API 수집(캐시-only write). krx_transform_daily 정합 → fill_set(진짜 부재 (Ticker,Date)) inner-join으로만 제한(APPEND-ONLY 원천보장·collision gate=0). OHLCV=KRX·meta/flags=티커 pre-gap template carry-forward·BM_Ret=Date canonical join(독립재계산 X)·Ret=chained(pre-gap Close부터)·source=krx_api_backfill_20260717. interior merge = rbind+unique(old우선)+temp-rename. ",
"★핵심 발견(seam parity): seam-end(07-02) stored Ret은 원래 KRX 07-01 Close 대비로 정확(미영속) — 5샘플 implied prevClose==KRX 07-01 5/5, 전수 216/216 07-02 recompute(Close07-02/Close07-01−1)==stored. 즉 07-01 채움만으로 recompute==stored 자동 성립(07-02 무변경=append-only 정합). ",
"★가드 5종(pre-write·실패시 write안함): g1 행수정확 14,009,624+8,856=14,018,480·g2 삭제0·g3 유니버스 행 2,370,544 불변·g4 maxDate 07-16 불변·g5 minDate 1990-01-05 불변 + collision0 + book-overlap0. ★parity 4종: P1 기존 14,009,624행 max|ΔClose|=max|ΔRet|=0·P2 source-seam 218→2·216/216 seam match·P3 유니버스 행 max|ΔRet|=0·P4 북14 71,125행 max|ΔRet|=0. ",
"★firewall: 정지-재개 2행(A004415 05-21·A032685 05-26, Vol=0 frozen→resume Vol>0 지문)은 |Ret|>1.0 물리불가 단일일 → Ret:=NA·Close 참값 보존(R44/R46 규칙+April fix 정직-NA 선례). 채운 8,856행 |Ret|>0.31=0(±30% 물리한계 內). ",
"★잔여: source-seam 2(A150840·A208340 penny 128~172원, 03-30~04-29 실미거래=KRX Close 부재=채울 데이터 없음, illiquidity 정직 잔여) + 27 old delisting(source_seam=FALSE·R47 표적 아님). 표적 216 fillable=100% 해소. ",
"★downstream: factor_db 재빌드 불요 — stored Ret 직접소비·canonical=유니버스 필터라 non-universe fill은 소비 factor 무영향(4월 사고=유니버스 momentum 오염이었으나 이번 구멍은 비-유니버스 전용). ",
"교훈: (1) 4월-사고 방어 = full-rebuild 금지·append-only(interior fill)·유니버스 행 불변 가드·행수 정확 가드가 mechanical 방어선. (2) seam-end stored Ret이 미영속 prevClose 대비 정확할 수 있으므로 구멍만 채우면 parity 자동 회복(day-after 수정 불요). (3) KRX 무수정주가는 stored seam과 정합(둘 다 KRX). (4) 미거래 penny는 fabricate 금지·정직 잔여. ",
"next_probe: P1(잔여 2 penny 대체소스/상장상태 재확인); P2(tripwire 리빌드 pre-hook 게이트화·R46 이월); P3(qw_refresh 수정주가 자동승격 검증)."),
  mechanism_hypothesis = "218 source-seam Close 구멍을 KRX 일별 재수집으로 append-only 채우면 recompute==stored parity가 회복되는가(기존·유니버스·북 무변경 유지하며). 실증: 8,856행 채움 → source-seam 218→2·216/216 07-02 recompute==stored·P1 기존 max|ΔRet|=0·P3 유니버스 max|ΔRet|=0·P4 북14 max|ΔRet|=0. 가드5종 PASS. 잔여 2=penny 미거래(데이터 부재). rawdata 실변경이나 유니버스/라이브 무영향.",
  core_reference = "R46 P1(KRX 백필·armed) stage_artifacts/WT_D20260715_015/verdict.json; R45 근원(Close hole·stored 참값) WT_D20260715_014; precedent project-rawdata-april-gap-incident-20260711(KRX 백필·가드5종 재사용)+reference-rawdata-ret-firewall-20260715; wiring krx_data_collector.R+krx_build_rawdata.R",
  metrics = list(
    task_class = "rawdata_integrity_repair_krx_backfill",
    verdict_type = "capability_established",
    rows_pre = 14009624L, rows_post = 14018480L, filled_rows = 8856L, filled_tickers = 216L, filled_dates = 41L,
    fill_set_target = 8902L, residual_non_traded = 46L, residual_seam_tickers = 2L,
    krx_live_days = 8L, krx_cache_days = 56L,
    universe_rows_pre = 2370544L, universe_rows_post = 2370544L,
    p1_max_abs_dret = 0.0, p1_max_abs_dclose = 0.0,
    tripwire_source_seam_before = 218L, tripwire_source_seam_after = 2L,
    tripwire_total_before = 245L, tripwire_total_after = 29L,
    seam_0702_recompute_eq_stored = 216L, seam_0702_total = 216L,
    book_rows_unchanged = 71125L, book_max_abs_dret = 0.0,
    halt_resumption_na = 2L, filled_ret_gt031 = 0L,
    all_guards_pass = TRUE, all_parity_pass = TRUE, n_trials = 1L,
    next_probe = c("잔여 2 penny 대체소스 (P1)", "tripwire 리빌드 pre-hook 게이트화 (P2)", "qw_refresh 수정주가 자동승격 검증 (P3)"),
    consumer_surfaces = c("①재료: seam 구멍 채움·완전성 회복", "⑧위험감시: tripwire pre-hook 후보", "⑨자본: 유니버스·북 parity 불변·라이브 무영향"),
    evidence = "stage_artifacts/WT_D20260715_016/{verdict,r47_parity_verify,r47_merge_guards}.json"),
  tags = c("data_integrity","krx_backfill","close_hole_repair","append_only","recompute_stored_parity",
           "non_universe","live_impact_zero","universe_rows_unchanged","book_unchanged",
           "april_gap_defense","guards_5_pass","parity_4_pass","integrity_line_complete",
           "non_capital","hygiene_layer","capability_established","rawdata_modified_scoped")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
