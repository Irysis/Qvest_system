setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")

## ── 1) close_round (capability_established — 방화벽 배선) ──────────────────────
source("02_Infrastructure/contracts/close_round.R")
rec <- close_round(
  round_id = "R44 (WT-D20260715_013, FQ-054 R1+R4)",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "R43이 적발한 canonical 입력단 구조적 취약(물리 불가능 Ret가 winsorize 방화벽 없이 통과)을 ",
    "함수 배선으로 수리 — 물리불가·0원제수·날짜갭은 HARD 격리(Ret:=NA), 분할류 잔여는 SUSPECT flag ",
    "(값유지·격리리스트, 분할 back-adjust는 R2/R3 리빌드 소관)로 두-단계 분류. 오염만 제거·정당 ",
    "데이터 불변(known-case parity 4-test 실증: 북 격리 0·월패널 max|Δ|=0·가드 clean 무해·monster 격리)."),
  next_probes = c(
    "다음 sanitize/factor_db 리빌드 시 방화벽 실적용 관측 — .cache/ret_firewall_isolation_<date>.csv n_isolated + factor_db Fwd_Ret(prod(1+Ret)) 재산출 대조(HARD 673 제거·유니버스 월패널 불변 실증). R2/R3 KRX 백필과 동시 실행 권장.",
    "가격제한 시변 정교화: 2015-06 이전 KR 일일제한 ±15% → 그 이전 구간 SUSPECT 경계를 0.16 시변 적용 검토(현재 0.31 균일). pre-2015 penny 오염(A063350/A025930 2007) 회수율 향상 여부.",
    "stored-Ret vs recompute Δ=4.86 근원 프로브 — 스토어드 rawdata Ret 컬럼이 Close/shift(Close)-1과 불일치하는 non-universe microcap 원인(Close 후수정·adj-close·중복일) 진단 → factor_db 직접소비(daily Ret) 오염 여부 확인."),
  consumer_surfaces = c(
    "①재료/데이터 원천: ret_sanity_firewall() 단일 진실 함수 + 격리리스트 상시 자산화 = canonical 입력단 물리불가 Ret 통과 봉쇄.",
    "⑧위험감시: ret_firewall_isolation CSV n_isolated 카운트 = 데이터-위생 tripwire(리빌드 로그 행수·|Ret|>0.31 급증 감시, R43 consumer ⑧ 구체화).",
    "⑨자본/운영: 현 북 14보유 방화벽 격리 0 — recon NAV clean 재확인(자본 무영향)."),
  frontier_update = "FQ-054 R1(canonical 입력단 방화벽)+R4(rawdata_sanitize Step5 강화) 배선 완료(armed→wired). 잔여: R2(April-gap seam)·R3(LS ELECTRIC 분할) = 별도 KRX 백필 리빌드(SUSPECT flag로 가시화만).",
  layer = "①재료(데이터 무결성 위생) — 성과 병목 아님. canonical 입력단 방화벽 배선.",
  evidence_refs = c(
    "verdict: stage_artifacts/WT_D20260715_013/verdict.json",
    "verify: stage_artifacts/WT_D20260715_013/verify_r44.R + _verify_r44_log.txt + r44_verify_results.json",
    "primary firewall: 02_Infrastructure/data/rawdata_sanitize.R (ret_sanity_firewall + Step5)",
    "secondary guards: 02_Infrastructure/contracts/canonical_screen_bt.R + 02_Infrastructure/ramp/factor_validation.R",
    "isolation lists: stage_artifacts/WT_D20260715_013/firewall_isolation_{IN_UNIVERSE,ALL}.csv",
    "parent R43: stage_artifacts/WT_D20260715_012/verdict.json"))
cat("\n[close_r44] marker 발행. verdict_type=", rec$verdict_type, "\n", sep="")

## ── 2) L-code emit (process·wiring — R39 선례 정합 metric_type) ───────────────
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R44_ret_sanity_firewall_wiring",
  grade = "B",
  metric_type = "canonical_screen",
  record_type = "process",
  construction_type = "ret_sanity_firewall(2-tier: HARD Ret:=NA[phys|Ret|>1.0/zerodiv prevClose<=10/dategap>20d] + SUSPECT flag[0.31<|Ret|<=1.0 값유지·격리리스트]) wired into rawdata_sanitize.Step5 + canonical_screen_bt/build_monthly_forward_returns Ret_1m assert",
  selection_type = "chain",
  lesson_text = paste0(
"[데이터무결성 방화벽 배선] R44 FQ-054 R1+R4 — R43 적발 'canonical 입력단 Ret winsorize 방화벽 부재'(물리불가 Ret 통과 구조취약) 수리. rawdata 직접수정 금지·함수 배선만·pin read-only·DART API 0·book/05_Production 무변경. ",
"★배선: (1차) rawdata_sanitize.R 신규 순수함수 ret_sanity_firewall(dt) — 물리불가(|Ret|>1.0)·0원제수(prevClose<=10)·날짜갭(>20d)=HARD Ret:=NA(후속 !is.na 제거 소비) / 분할류 잔여(0.31<|Ret|<=1.0)=SUSPECT 값유지+격리리스트 기록(.cache/ret_firewall_isolation_<date>.csv). Step5 '|Ret|>0.3 로깅만'→방화벽 적용. rawdata 스키마 불변(임시 prevClose/gapdays 후 제거)·Ret 재계산식 동일(parity). (2차 이중가드) canonical_screen_bt/build_monthly_forward_returns가 Ret_1m 소비 전 물리불가(>5.0 or <-1.0) assert(warn+NA·본판정 비중단). ",
"★회귀검증 4-test 전부 PASS(known-case parity): A)방화벽 census — 유니버스內 17/17 R43 정확 일치(1 HARD=A063350 2007 phys-impossible + 16 SUSPECT[LS ELECTRIC·루닛·코미코 포함]); HARD 672(phys257/zerodiv373/dategap42)·SUSPECT 2121. B)현 북 14보유 격리 0행(R43 오염 ZERO 재확인). C)유니버스 월패널 前/後 max|Δ Ret_1m|=0·상이 0행(HARD는 전부 월중일→월말 asof close 불변). D)canonical 가드 clean 월패널(5785 종목-월) 0경고·PORT_t 불변 + Ret_1m=67000 monster 주입 시 1회 발화·격리→결과 finite·clean과 bit-일치. ",
"교훈: 두-단계(HARD 삭제 vs SUSPECT 보존) = 물리불가만 확정삭제, 분할류 ambiguous는 flag-only(삭제≠수리, back-adjust는 R2/R3 KRX 백필 리빌드 소관). megacap 정당이동·limit-bound(<=0.30) 불변 = reference-kr-2025-megacap 준수(수치 커서 오염 단정 금지). stored Ret vs recompute Δ=4.86(non-universe microcap) = 별개 위생 프로브 후보. ",
"규율: wiring only·n_trials=1(chain·DSR 부적용, 데이터무결성-face). 잔여 R2(April-gap seam)/R3(LS ELECTRIC ~1:4.4 분할) = 별도 리빌드(SUSPECT flag로 가시화). ",
"next_probe: P1(리빌드 시 실적용 관측·factor_db Fwd_Ret 대조); P2(가격제한 시변 pre-2015 ±15% SUSPECT 경계 0.16); P3(stored-Ret vs recompute Δ=4.86 근원 진단)."),
  mechanism_hypothesis = "canonical 입력단에 Ret winsorize 방화벽을 배선하면(물리불가=HARD NA·분할류=SUSPECT flag) 오염 상존 vintage에서도 소비면(canonical/월패널)이 보호되는가. 실증: 오염 672행(HARD)만 제거·정당 데이터 전부 불변(북0·월패널Δ0·가드 clean무해). 방화벽=오염제거이지 데이터수정 아님(분할 back-adjust는 리빌드 소관).",
  core_reference = "FQ-054 R43 census(WT-D20260715_012 Ret winsorize 방화벽 부재 적발); R43 verdict stage_artifacts/WT_D20260715_012/verdict.json; wiring 02_Infrastructure/data/rawdata_sanitize.R + contracts/canonical_screen_bt.R + ramp/factor_validation.R; verify stage_artifacts/WT_D20260715_013/",
  metrics = list(
    task_class = "data_integrity_firewall_wiring",
    verdict_type = "capability_established",
    firewall_tiers = "HARD(Ret:=NA: phys|Ret|>1.0 / zerodiv prevClose<=10 / dategap>20d) + SUSPECT(flag·값유지: 0.31<|Ret|<=1.0)",
    hard_total = 672L, suspect_total = 2121L, in_universe_iso = 17L, in_universe_hard = 1L,
    book_isolated = 0L, panel_max_delta = 0.0, guard_clean_warns = 0L, guard_monster_caught = 1L,
    overall_pass = TRUE, n_trials = 1L,
    next_probe = c("리빌드 실적용 관측 (P1)", "가격제한 시변 pre-2015 (P2)", "stored-Ret Δ 근원 (P3)"),
    consumer_surfaces = c("①재료: ret_sanity_firewall 단일진실+격리리스트", "⑧위험감시: n_isolated tripwire", "⑨자본: 북 recon clean"),
    evidence = "stage_artifacts/WT_D20260715_013/verdict.json + r44_verify_results.json"),
  tags = c("data_integrity","ret_sanity_firewall","wiring_only","canonical_input_guard",
           "two_tier_isolation","hard_na","suspect_flag","known_case_parity","non_capital",
           "hygiene_layer","capability_established","rawdata_unchanged","april_gap_residual_r2r3")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
