setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")

## ── 1) close_round (capability_established — 배선 정련·무결성 라인 완결) ──────────
source("02_Infrastructure/contracts/close_round.R")
rec <- close_round(
  round_id = "R46 (WT-D20260715_015, FQ-054 P2+P3)",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "R45 근원 지식(date-gap 불일치=Close-hole span recompute 스퓨리어스·stored Ret 참값)을 방화벽·게이트로 제도화. ",
    "P3: ret_sanity_firewall date-gap 분기에서 |stored|≤0.31이면 NA 대신 stored 참값 복원(RESTORE) — recompute magnitude 무관",
    "(date-gap이 phys/zerodiv보다 우선, restore carve-out), stored 무효면 HARD 유지. P2: close_continuity_tripwire — ",
    "리빌드 전 활성상장 Close gapdays>20 hole 감지(source seam 지문). 6-test parity: HARD 672→633(seam 39건 RESTORE 이관)·",
    "유니버스 분류 불변(iso 17=1phys+16suspect·restore_univ 0)·북 격리 0·유니버스 월패널 max|Δ|=0·canonical 가드 불변·",
    "tripwire 유니버스內 활성 구멍 0(gate clean). rawdata/book/05_Production/factor_db 무변경(입력단 함수 배선만)."),
  next_probes = c(
    "KRX 백필 리빌드(별도 태스크·armed): tripwire 감지 245 활성 Close 구멍(2026-04-30→07-01 April + 07-03/06 July seam·218 source-seam·전량 비-유니버스) KRX 일별 재수집 → recompute==stored parity 회복 + 157 소폭 seam 동시 해소. April-gap R2/R3 잔여와 동시(rawdata 직접수정 금지·KRX 백필 경유). 차기 리밸 유니버스 진입 후보 우선.",
    "tripwire 게이트화(선택): close_continuity_tripwire를 factor_db 리빌드 pre-hook으로 승격 — 현재 sanitize Step 4b report-only(warn)에서 유니버스內 활성 구멍 발생 시 hard-block(April-gap 실데이터 삭제 사고류 사전차단, Step 3 캘린더-hole 가드 정합).",
    "pre-2015 가격제한 시변(선택): ret_limit=0.31(2015+ ±30%)을 pre-2015 ±15%(0.16 임계)로 시변 검토(R44 P2 잔존)."),
  consumer_surfaces = c(
    "①재료/데이터 원천: ret_sanity_firewall date-gap 정련 = seam 참값(stored Ret) 정보손실 방지 배선(39건 복원). Close 연속성 tripwire = 리빌드 전 구멍 조기감지 단일함수(source seam 지문). R45 '근원=Close hole·stored 참값' 지식을 로직으로 제도화.",
    "⑧위험모델/감시: close_continuity_tripwire gate_flag_in_universe_active = 새 데이터-위생 게이트 신호(리빌드 전 유니버스內 활성 구멍 경보). Ret firewall(사후 artifact 격리)과 상보(사전 근원 감지).",
    "⑨자본/운영: 현 북 14보유·유니버스 월패널·유니버스內 활성 구멍 0 = 정련 후에도 known-case parity 불변(recon NAV clean)."),
  frontier_update = "FQ-054 P2(Close 연속성 tripwire)+P3(firewall date-gap stored 보존) 소비 완료 — 밤샘 무결성 라인(R42→R43→R44→R45→R46) 배선 완결. 잔여 근본수리=KRX 백필 리빌드(R2/R3·armed, 245 구멍 표적).",
  layer = "①재료(데이터 무결성 위생) — 성과 병목 아님. R45 P2+P3 소비로 seam 근원 지식을 방화벽 정련(참값 보존)·tripwire(사전 감지)로 배선.",
  evidence_refs = c(
    "verdict: stage_artifacts/WT_D20260715_015/verdict.json",
    "verify: stage_artifacts/WT_D20260715_015/verify_r46.R + r46_verify_results.json + _verify_r46_log.txt",
    "parsecheck+unit: stage_artifacts/WT_D20260715_015/_parsecheck.R",
    "chart: stage_artifacts/WT_D20260715_015/chart_r46_integrity.png",
    "wiring: 02_Infrastructure/data/rawdata_sanitize.R (ret_sanity_firewall P3 + close_continuity_tripwire P2 + Step4b/Step5 배선)",
    "tripwire report: stage_artifacts/WT_D20260715_015/close_continuity_holes_r46.csv",
    "parent R45: stage_artifacts/WT_D20260715_014/verdict.json (P2+P3 next_probe)"))
cat("\n[close_r46] marker 발행. verdict_type=", rec$verdict_type, "\n", sep="")

## ── 2) L-code emit (process·wiring — R44/R45 선례 정합) ────────────────────────
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R46_firewall_dategap_refine_close_tripwire",
  grade = "B",
  metric_type = "canonical_screen",
  record_type = "process",
  construction_type = "ret_sanity_firewall date-gap 참값보존(P3) 배선 + close_continuity_tripwire(P2) 신규 배선 + sanitize Step4b/Step5 배선 + 6-test 회귀 parity",
  selection_type = "chain",
  lesson_text = paste0(
"[데이터무결성 배선정련] R46 FQ-054 P2+P3 — R45 근원 지식(date-gap 불일치=Close 시계열 구멍 span recompute 스퓨리어스·stored Ret 참값)을 방화벽·게이트로 제도화. read-only(pin)·rawdata/book/05_Production/factor_db 무변경(입력단 함수 배선만)·DART API 0·단일스레드·io(2). ",
"★P3(firewall date-gap 정련): ret_sanity_firewall date-gap(gapdays>20) 분기에서 |stored Ret|≤0.31(물리타당)이면 NA 격리 대신 stored 참값 복원(RESTORE, mask_restore). ★핵심 설계: recompute(Close/shift(Close)-1) magnitude 무관 — date-gap이면 recompute 자체가 Close-hole을 gap 넘어 참조한 스퓨리어스(|recompute|>1.0 phys·penny 포함)이므로 date-gap이 phys/zerodiv보다 우선(restore carve-out). date-gap ∧ stored 무효(|stored|>0.31 or NA)는 HARD NA 유지, 연속일(non-gap) phys·0원제수만 HARD(stored도 오염). stored 참조는 Ret_stored 컬럼(Step5 recompute 전 보존) 우선. ",
"★P2(Close 연속성 tripwire): close_continuity_tripwire — 리빌드 전 활성상장(최종관측일이 데이터셋 max 90일 이내) Close gapdays>20 hole 감지·리포트. gap_threshold=20d(KR 최장연휴 ~9d 초과=진성 구멍). in_universe/active_listed/source_seam(krx_api_backfill→krx_api 경계)/recent 태깅 + gate_flag(유니버스內 활성 구멍>0). sanitize Step4b report-only 배선. Ret firewall(사후 artifact 격리)과 상보(사전 근원 감지). ",
"★6-test 회귀 parity ALL PASS(known-case): A)census recompute-basis |Ret|>0.31=2793·HARD 633(R44 672−39 restore)·RESTORE 39·SUSPECT 2121·유니버스 분류 불변(iso 17=1 phys HARD[A063350]+16 suspect·restore_univ 0) B)북 14보유 격리 0 C)RESTORE 39 전량 비-유니버스→유니버스 월패널 OLD(hard-drop) vs NEW(hard-NA+restore) max|Δ Ret_1m|=0·book max|Δ|=0·+39행 보존 D)canonical 가드 clean(경고0)+monster catch(1발화·finite·bit일치) E)R45 196 seam: RESTORE 39(|recompute|>0.31 date-gap·stored 물리타당 전량)·HARD 0·SUSPECT 0·미발화 157(|recompute|≤0.31 임계미달·OLD/NEW 동일)·worked example A004415 recompute +489%→stored +2.93% 보존 F)tripwire 현 rawdata: 245 구멍·241종목·유니버스內 0·source-seam 218·gate CLEAN. ",
"★잔여(별도 리빌드): 157 소폭 seam(|recompute|≤0.31 방화벽 임계 미도달, scope 정합)·245 활성 Close 구멍(전량 비-유니버스 April/July seam) = 근원(Close hole) 수리 소관 = KRX 일별 재수집(R2/R3 April-gap 리빌드와 동시·rawdata 직접수정 금지). 리빌드 후 recompute==stored parity 회복(P1). ",
"교훈: 근원 지식(R45 '큰 recompute=Close-hole 증상·stored 참값')을 방화벽 로직에 반영할 때 우선순위가 핵심 — date-gap seam은 recompute가 phys-불가 magnitude여도 그것이 곧 hole 지문이므로 phys 분기보다 우선 처리해야 참값(stored)이 보존된다(초기 phys-우선 설계는 A004415 restore 실패→date-gap 우선으로 정정). tripwire=사전 근원 감지 + firewall=사후 artifact 격리 = 상보. 밤샘 무결성 라인 R42~R46 배선 완결. ",
"next_probe: P1(KRX 백필 리빌드·245 구멍 표적·parity 회복); P2(tripwire 리빌드 pre-hook 게이트화); P3(pre-2015 가격제한 시변 임계)."),
  mechanism_hypothesis = "R45 근원(date-gap 불일치=Close-hole span recompute 스퓨리어스·stored 참값)을 방화벽에 반영: date-gap ∧ stored 물리타당이면 stored 복원(RESTORE)이 date-gap ∧ stored 무효(HARD)·연속일 phys/zerodiv(HARD)와 분리되는가. 실증: 6-test parity — HARD 672→633(seam 39 RESTORE 이관)·유니버스 분류 불변·유니버스 월패널 max|Δ|=0·A004415 recompute+489%→stored+2.93% 보존. tripwire 245 구멍 감지·유니버스 활성 0(gate clean). 정련·게이트 배선만·rawdata 무변경.",
  core_reference = "FQ-054 P2(Close 연속성 tripwire)+P3(firewall date-gap stored 보존); R45 verdict stage_artifacts/WT_D20260715_014/verdict.json(근원=Close hole); R44 L-RAMP-20260715_070019(방화벽 배선); wiring 02_Infrastructure/data/rawdata_sanitize.R; precedent project-rawdata-april-gap-incident-20260711 + project-stored-panel-samemonth-lookahead",
  metrics = list(
    task_class = "data_integrity_wiring_refinement",
    verdict_type = "capability_established",
    hard_before_r44 = 672L, hard_after_r46 = 633L, restore = 39L, restore_in_universe = 0L,
    suspect = 2121L, iso_in_universe = 17L, inuniv_hard_phys = 1L, inuniv_suspect = 16L,
    r45_196_restore = 39L, r45_196_untouched_le031 = 157L,
    universe_panel_max_delta = 0.0, book_iso_rows = 0L,
    tripwire_holes = 245L, tripwire_unique_tickers = 241L, tripwire_in_universe = 0L,
    tripwire_source_seam = 218L, tripwire_gate_flag = FALSE,
    worked_example = "A004415_2026-07-02_recompute_+4.89_stored_+0.0293_restored",
    all_6_tests_pass = TRUE, n_trials = 1L,
    next_probe = c("KRX 백필 리빌드 245 구멍 (P1)", "tripwire 리빌드 pre-hook 게이트화 (P2)", "pre-2015 가격제한 시변 (P3)"),
    consumer_surfaces = c("①재료: firewall 참값보존+tripwire 사전감지", "⑧위험감시: Close 연속성 gate 신호", "⑨자본: 북·유니버스 parity 불변"),
    evidence = "stage_artifacts/WT_D20260715_015/verdict.json + r46_verify_results.json"),
  tags = c("data_integrity","wiring_refinement","firewall_dategap_restore","close_continuity_tripwire",
           "stored_ret_authoritative","known_case_parity","non_universe","live_impact_zero",
           "integrity_line_complete","non_capital","hygiene_layer","capability_established",
           "rawdata_unchanged","krx_backfill_armed","r45_rootcause_institutionalized")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
