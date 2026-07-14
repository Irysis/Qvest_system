setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")

## ── 1) close_round (capability_established — 근원 진단·소비면 전개) ──────────
source("02_Infrastructure/contracts/close_round.R")
rec <- close_round(
  round_id = "R45 (WT-D20260715_014, FQ-054 P3)",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "R44 P3(stored Ret vs recompute max|Δ|=4.86) 근원 규명 — 불일치 196 종목-일(0.0014%)의 원인은 ",
    "Close 시계열 구멍(결측 거래일): recompute Close/shift(Close)-1이 stale prevClose를 gap 넘어 참조해 ",
    "스퓨리어스, stored Ret 컬럼은 참값(100% |Ret|<=0.31 물리타당). 2 cluster: 161건@prevDate 04-29(64일 ",
    "hole=April-gap 비-유니버스 잔여) + 35건@prevDate 07-02(5일 seam). 중복일/adj-close/파싱 전부 반증. ",
    "유니버스內 0건·현 북 14보유 hole 0 → 라이브 무영향. factor_db(prod(1+Ret)=stored 소비)는 stored 참값이라 오염 아님."),
  next_probes = c(
    "KRX 백필 완결(수리 경로): 196 비-유니버스 종목 04-30→07-01+07-03/06 Close 구멍 재수집 → recompute==stored parity 회복. April-gap R2/R3 잔여와 동시. 차기 리밸 유니버스 진입 후보 우선.",
    "Close-series 연속성 tripwire: factor_db 리빌드 전 활성상장 중 gapdays>20 hole 감지 게이트 추가(source seam krx_api_backfill_*→krx_api 경계 발화). Ret firewall(recompute 산물 격리)과 상보.",
    "firewall 방향 정합(선택): ret_sanity_firewall date_gap HARD에서 |stored|<=0.31이면 stored Ret 보존·recompute만 폐기 — stored 참값 정보손실 방지(비-유니버스라 저EV)."),
  consumer_surfaces = c(
    "①재료/데이터 원천: stored Ret = KRX-sourced 참값(recompute은 gap 넘어 스퓨리어스). factor_db 직접소비(prod(1+Ret))는 오염 아님. R44 P3 프레이밍(stored 오염 의심) 반전 기록.",
    "⑧위험모델/감시: Close-series 연속성(gapdays>20 hole) = 새 데이터-위생 tripwire 후보 — 현 Ret firewall과 상보(source seam 경계 지문).",
    "⑨자본/운영: 현 북 14보유·유니버스 348종목 hole 0 = 라이브 factor 무영향 근원까지 재확인(recon NAV clean)."),
  frontier_update = "FQ-054 P3(stored-Ret vs recompute Δ 근원) 소비 완료 — 근원=Close 시계열 구멍(April-gap 비-유니버스 잔여), stored Ret 참값, 라이브 무영향. 수리는 R2/R3 KRX 백필과 동시(armed). 신규: Close-series 연속성 tripwire 후보.",
  layer = "①재료(데이터 무결성 위생) — 성과 병목 아님. R44 P3 근원 진단(Close-hole·비-유니버스·라이브 무영향).",
  evidence_refs = c(
    "verdict: stage_artifacts/WT_D20260715_014/verdict.json",
    "census: stage_artifacts/WT_D20260715_014/census_r45.R + _census_log.txt + census_summary.json",
    "drill: stage_artifacts/WT_D20260715_014/census_drill.R + _drill_log.txt",
    "gap verify: stage_artifacts/WT_D20260715_014/verify_gap.R + _verify_gap_log.txt",
    "census csv: stage_artifacts/WT_D20260715_014/mismatch_census_{ALL,IN_UNIVERSE}.csv",
    "consumption: 02_Infrastructure/factor_db/factor_db_builder.R L1325/L1508(prod(1+Ret)) + contracts/canonical_screen_bt.R L40(Close recompute) + 05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R L62(univ filter)",
    "parent R44: stage_artifacts/WT_D20260715_013/verdict.json (P3 next_probe)"))
cat("\n[close_r45] marker 발행. verdict_type=", rec$verdict_type, "\n", sep="")

## ── 2) L-code emit (process·diagnosis — R44 선례 정합) ────────────────────────
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R45_stored_ret_vs_recompute_rootcause",
  grade = "B",
  metric_type = "canonical_screen",
  record_type = "process",
  construction_type = "stored Ret vs recompute(Close/shift(Close)-1) 전수 census(14M행) + 2-cluster gap-seam 근원 진단 + factor_db/canonical 소비경로 추적 + 라이브 북 hole 점검",
  selection_type = "chain",
  lesson_text = paste0(
"[데이터무결성 근원진단] R45 FQ-054 P3 — R44가 남긴 'stored Ret vs recompute max|Δ|=4.86(non-universe microcap) 근원' 프로브 소비. read-only(pin)·rawdata/book/05_Production/factor_db 무변경·DART API 0. ",
"★census(14,004,246행): |Δ|>0.01 = 196 종목-일(0.0014%)·max|Δ|=4.8634·중복(Ticker,Date)키 0·유니버스內 0(전건 비-유니버스: 우선주 34+Name-NA 소형 138). 규모분포 0.01-0.05:42/0.05-0.10:28/0.10-0.30:87/0.30-1.0:35/>1.0:4. 전건 2026(07-02:160·07-07:35·05-04:1). ",
"★근원 = Close 시계열 구멍(missing intervening trading days): recompute Close/shift(Close)-1이 stale prevClose를 gap 넘어 참조해 스퓨리어스, stored Ret 컬럼은 참값(방향판정: |stored|<=0.31 물리타당 196/196=100% vs |recompute|<=0.31 157/196=80.1%). 2 cluster — 161건@prevDate 2026-04-29(gapdays=64, April-gap 비-유니버스 잔여, source seam krx_api_backfill_20260711→krx_api) + 35건@prevDate 2026-07-02(gapdays=5, 07-03/06 결측 소형 seam). worked example A004415: 04-29 Close=1193 → 07-02 Close=7030(04-30~07-01 전 결측), stored Ret=+2.9%(정상) vs recompute=+489%(hole-spanning). ",
"★반증: adj-close/배당분할 아님(adj 컬럼 부재·ratio 정수배 지문 아님)·중복일 아님(dup키 0)·파싱오류 아님(stored 100% 제한내). ",
"★factor_db 소비경로: factor_db_builder Fwd_Ret/IC = prod(1+Ret) → stored 직접소비 = seam 케이스 stored 참값이라 오염 아님(recompute 안 함). compute_momentum(M08)·risk 동일. canonical_screen_bt = Close1/Close0-1 재계산 노출 가능하나 유니버스필터(196 전건 비-유니버스 미선택)+양쪽 월말Close 필요로 보호. → 어느 소비면도 실질 오염 없음. ",
"★라이브: 현 북 STR_1715_on_M4_R05_noLayer4_PG2 score_eff 7팩터(CORE C01_SUE/C02_EPS_Chg_1m/C04_ESBR/C06_TP_Gap + DEF Q07/M08_Residual_Mom/Q25) = _recompute_alpha_asof.R L62 유니버스필터 → 196 불일치 종목 0 선택. 북 14보유 max_gapdays=4·hole 0(삼성전자 04-27~07-08 49거래일 연속). 유니버스 348종목 04-30~07-01 41/41일(hole<30일 0). 라이브 factor 영향 ZERO. ",
"★R44 프레이밍 반전: R44 P3의 'stored Ret 불일치 원인(Close 후수정·adj-close·중복일)→factor_db 오염 여부'는 stored-Ret 오염이 아니라 recompute 산물 — Δ=4.86은 stored 컬럼 결함이 아니라 Close-hole의 증상. stored가 참값. ",
"교훈: recompute Ret은 Close-series 연속성에 민감(gap 넘어 stale prevClose) — stored Ret이 KRX-sourced 참값. 데이터-위생 census는 '큰 수치=오염' 단정 금지, 방향판정(제한내 비율)으로 참값 식별(reference-kr-2025-megacap 정합). April-gap 사고 잔여가 비-유니버스에 상존하나 라이브 무영향. ",
"수리: 196 종목 Close 구멍 KRX 백필(R2/R3와 동시, rawdata 직접수정 금지) + Close-series 연속성 tripwire(gapdays>20) 배선. next_probe: P1(KRX 백필 완결·parity 회복); P2(Close 연속성 tripwire); P3(firewall date_gap에서 stored 보존 정교화)."),
  mechanism_hypothesis = "stored Ret vs recompute 불일치는 stored 컬럼 오염인가 recompute 산물인가. 실증: recompute이 Close 시계열 구멍(결측 거래일)을 gap 넘어 stale prevClose로 계산한 스퓨리어스이며 stored Ret이 참값(제한내 100% vs 80.1%). factor_db(stored 소비)는 오염 아님·유니버스 0건·라이브 무영향. 근원=April-gap 비-유니버스 잔여 Close-hole.",
  core_reference = "FQ-054 P3(R44 stored-Ret Δ=4.86 근원 프로브); R44 verdict stage_artifacts/WT_D20260715_013/verdict.json; census stage_artifacts/WT_D20260715_014/; consumption factor_db_builder.R L1325/L1508 + canonical_screen_bt.R L40 + _recompute_alpha_asof.R L62; precedent project-rawdata-april-gap-incident-20260711",
  metrics = list(
    task_class = "data_integrity_root_cause_diagnosis",
    verdict_type = "capability_established",
    n_mismatch_gt001 = 196L, max_dAbs = 4.8634, pct_of_comparable = 0.0014,
    in_universe = 0L, dup_keys = 0L,
    stored_within_limit_pct = 100.0, recompute_within_limit_pct = 80.1,
    root_cause = "Close_series_hole(missing_trading_days)_recompute_spurious_stored_authoritative",
    cluster1 = "161@prevDate_2026-04-29_gapdays64_aprilgap_nonuniverse_residual",
    cluster2 = "35@prevDate_2026-07-02_gapdays5_july_seam",
    factor_db_contaminated = FALSE, live_book_impact = "ZERO",
    book_holdings_hole = 0L, universe_hole_gt30d = 0L, n_trials = 1L,
    next_probe = c("KRX 백필 완결 (P1)", "Close 연속성 tripwire (P2)", "firewall stored 보존 정교화 (P3)"),
    consumer_surfaces = c("①재료: stored=참값·factor_db 오염아님", "⑧위험감시: Close 연속성 tripwire", "⑨자본: 북 hole 0 recon clean"),
    evidence = "stage_artifacts/WT_D20260715_014/verdict.json + census_summary.json"),
  tags = c("data_integrity","root_cause_diagnosis","stored_ret_authoritative","recompute_artifact",
           "close_series_hole","april_gap_residual","non_universe","factor_db_not_contaminated",
           "live_impact_zero","known_case_parity","non_capital","hygiene_layer",
           "capability_established","rawdata_unchanged","r44_framing_corrected")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
