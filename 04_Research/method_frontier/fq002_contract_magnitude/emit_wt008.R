# emit_wt008.R — WT-D20260803_008 산출물 발행 (alpha_validation + lineage + L-code)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
WT <- "WT-D20260803_008"; STG <- "stage_artifacts/WT_D20260803_008"
MBX <- file.path("qepm/mailbox/worktask", WT)
dir.create(STG, recursive = TRUE, showWarnings = FALSE)

R  <- fromJSON(file.path(OUTD, "fq125_stage1_results.json"), simplifyVector = TRUE)
C  <- fromJSON(file.path(OUTD, "fq125_stage1_controls.json"), simplifyVector = TRUE)
RB <- fromJSON(file.path(OUTD, "fq125_stage1_regime_robust.json"), simplifyVector = TRUE)
V  <- fromJSON(file.path(OUTD, "gridx_vintage_compare.json"), simplifyVector = TRUE)
cn <- R$canonical_A_size

val <- list(
  task_id = WT, agent = "alpha-research", emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis_id = "FQ-125",
  strategy_id = "FQ125_CTR_MAG_12M_MCAP_stage1",
  metric_type_map = list(
    ic_family = "diagnostic_statistic (Spearman cor — 백테스트 합성 아님)",
    portfolio_family = "canonical_screen (canonical_screen_bt 실측)",
    graduation_authority = "forge build_bt_result — 본 라운드 미실행. HARD 3종 판정 불가/미주장"),
  gate_eligible = FALSE,
  interim_gate = list(
    rule_fixed_by = "WT-D20260802_023/preregistration.json (측정 전 고정, 사후 변경 없음)",
    rule = "PASS: combined t_NW>=1.5 AND new-segment mean IC>0 AND regime decomposition / ABORT: combined t_NW<1.0 / else INDETERMINATE",
    combined = R$gate$combined, new_segment = R$gate$new_segment, pilot_segment = R$gate$pilot_segment,
    regime_decomposition_performed = TRUE,
    verdict = R$gate$verdict),
  parity = R$parity_pilot,
  corpus = R$corpus,
  measurement_provenance = list(
    grid_vintage = R$grid_vintage, pinned_pilot_vintage = V$vintage_pinned,
    identical_vintage = V$identical_vintage, overlap_compare = V$compare,
    bench_source_defect = V$bench_source_defect,
    panel = R$panel, coverage = R$coverage),
  regime = R$regime,
  regime_exante = list(
    honesty = "사전등록되지 않은 사후 선택(동월/lag1/trailing3 3-way look). 확정 주장 아님 — 다음 라운드 사전등록 대상.",
    observed = RB$observed, permutation = RB$R1_permutation,
    threshold_sweep = RB$R2_threshold_sweep, era_replication = RB$R3_era_replication,
    consumption_conditional = list(
      unconditional_port_t = RB$R4_consumption$unconditional$portfolio_alpha_t_nw_lag3,
      unconditional_n = RB$R4_consumption$unconditional$n_months,
      broad_led_port_t = RB$R4_consumption$broad_led_only$portfolio_alpha_t_nw_lag3,
      broad_led_n = RB$R4_consumption$broad_led_only$n_months,
      broad_led_net_sr = RB$R4_consumption$broad_led_only$net_sr,
      caveat = RB$R4_consumption$caveat)),
  controls = list(
    canary = C$C0_canary,
    size_alternative = C$C1_size_alternative[c("base", "pure_size", "size_explained_share")],
    size_residualized = C$C2_size_residualized[c("summary", "gap_retention", "cross_sec_rho_mean")],
    exante_regime = C$C3_exante_regime,
    composition = C$C4_composition),
  pit = list(
    c5_cutoff = "신호월 말일 컷오프 — rcept_dt <= 신호월 말일 공시만 누적",
    lag1_stress = R$lag1_stress,
    violation_injection = R$violation_injection_correction_backdate,
    ast_gate = "ast_spec_gate FAIL_LOOKAHEAD 1회 발화 후 decision_ts 컨벤션 정정 → 통과"),
  transition_wall = list(
    canonical_cap_w_port_t = cn$portfolio_alpha_t_nw_lag3,
    canonical_pvalue = cn$portfolio_alpha_t_pvalue,
    canonical_n_months = cn$n_months,
    ew_universe_port_t = cn$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    net_sr = cn$net_sr, information_ratio = cn$information_ratio,
    alpha_annualized = cn$alpha_annualized, turnover_annual = cn$turnover_annual,
    cap_tier_weight_share = cn$diag_cap_tier$weight_share_avg,
    cap_tier_contrib_annualized = cn$diag_cap_tier$contrib_gross_annualized,
    note = "graduation HARD PORT_t 2.95 미달. IC 확립과 별개 관문 — 랭킹 소비 자격 없음."),
  perturbation = R$perturbation[setdiff(names(R$perturbation), "draws")],
  payment_recommendation = list(
    stage1_verdict = "PASS",
    remaining_scope_reassessed = "2008~2018 확장은 **현행 파서로 불가**. 2017-03~2018-12 실측 OK 2.4%(29/1199) — PARSER_ERROR 620 + UNZIP_FAIL 527. 큐의 '2008-01까지 원문 존재'는 문서 존재 여부이지 파싱 가능성이 아니다.",
    recommendation = "잔여 구간 크롤 지불 **보류** — 지불 전 파서 조건부 게이트 선행",
    numeric_conditions = list(
      precondition = "2017/2016/2014/2012/2010 각 연도 무작위 30건 샘플 파싱 성공률 >= 90% (비용 150 호출, 캐시 존재분 우선)",
      then_stage2_scope = "2015-01~2018-12 (48개월, ~4,000 호출) 우선 — 연속성 확보가 2008 점프보다 통계 가치 높음",
      stage2_gate = "합산 n>=127 에서 t_NW >= 2.0 AND 신규 48개월 mean IC > 0",
      abort = "샘플 성공률 < 90% 이면 파서 수리가 선행 과제 — 크롤 지불 없음"))
)
write_json(val, file.path(STG, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 8, null = "null")
cat("[emit] →", file.path(STG, "alpha_validation.json"), "\n")

# ── lineage (alpha_package.json write 이후 순서 — L-194) ────────────────────
stopifnot(file.exists(file.path(MBX, "alpha_package.json")))
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT, package_type = "alpha_package",
  method_selected = "CTR_MAG_12M_MCAP (12M 누적 계약금액/시총) — 창 확장 79 IC월 재측정, interim 게이트 PASS",
  input_file_paths = c(list.files(".cache/dart/contract_backfill", pattern = "^\\d{6}\\.csv$",
                                  full.names = TRUE)[c(1, 25, 60, 113)],
                       file.path(OUTD, "panelx_A.parquet"),
                       file.path(OUTD, "gridx_returns.parquet"),
                       file.path(OUTD, "gridx_bench.parquet"),
                       file.path(OUTD, "gridx_universe_size.parquet"),
                       file.path(OUTD, "gridx_liq.parquet")))
cat("[emit] lineage 기록 완료\n")

# ── L-code 아티팩트 ────────────────────────────────────────────────────────
LD <- "stage_artifacts/l_code/alpha_research"; dir.create(LD, recursive = TRUE, showWarnings = FALSE)
lc <- list(
  l_code_id = "L-WT_D20260803_008_FQ125_CONTRACT_REGIME_CONDITIONAL",
  emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "alpha-research", mode = "QPM", task_id = WT, hypothesis_id = "FQ-125",
  metric_type = "canonical_screen + diagnostic_statistic",
  title = "계약수주 magnitude 는 확립된 IC lead 이나 무조건 랭킹으로는 전이 벽 — 국면(횡단면 저변) 조건부에서만 살아난다",
  finding = paste(
    "2019-12~2026-06 79 IC월 실측: 평균 rank-IC +0.0565, t_NW(lag3) +1.994, ICIR 0.234, 양수월 59.5%.",
    "사전 고정 interim 게이트(t_NW>=1.5 AND 신규구간 mean IC>0 AND 국면분해) PASS.",
    "신규 55개월 단독 +0.0460 (t_NW 1.294) — 파일럿 24개월(+0.0806)보다 낮으나 부호·방향 재현.",
    "섭동 120 draws q05 t_NW = +1.755 (파일럿 1.441 대비 개선).",
    "★감쇠의 정체 = 벤치 방향이 아니라 **횡단면 저변(mega-cap 주도 여부)**.",
    "파일럿에서 관측된 corr(IC, BM_Ret) -0.2545 는 n=79 에서 -0.0297 로 소멸 — 그 해석은 표본 아티팩트였다.",
    "실측 축은 mega_spread(시총 top10 평균수익 − 유니버스 중앙수익): corr(IC, mega_spread) = -0.3459.",
    "동월 분할 저변주도 28M +0.1968(t 5.33) vs 대형주주도 51M -0.0205(t -0.63).",
    "★사전관측 가능한 t-1 상태로 바꿔도 분리 잔존: 저변 27M +0.1445(t_NW 5.17) vs 대형 52M +0.0108(t_NW 0.32),",
    "격차 +0.1337, 라벨 순열 p=0.0082, 문턱 스윕 q0.2~0.5 안정, 신규 구간 단독 재현(격차 +0.103 t_NW 5.84).",
    "단 국면 축 선택은 사후(3-way look) — 확정 아님.", sep = " "),
  mechanism_diagnosis = paste(
    "신호 보유 포트의 시총 tier 실측 = MEGA 0.25% / MID 5.5% / OTHER 94.2%.",
    "자금이 초대형주로 쏠리는 국면에는 이 계층 전체가 가격발견에서 배제돼 '기관 후속 유입' 경로가 끊긴다.",
    "따라서 국면 의존은 사후 발견이 아니라 메커니즘에서 도출 가능한 경계다.",
    "★사이즈 틸트 대안은 기각: 순수 1/Size 는 같은 유니버스에서 평균 IC +0.0151(t_NW 0.63)에 불과하고,",
    "size-잔차화 후에도 계약 신호의 IC +0.0558(t_NW 2.005, 98.8% 보존)·국면 격차 98.5% 보존.",
    "score~1/Size 월별 단면 상관 평균 -0.012 = 사실상 직교.", sep = " "),
  transition_wall = paste(
    "무조건 canonical cap-w PORT_t = +0.511 (p 0.61, n=79), EW-uni +1.604, net_SR 0.186, TO 1.82/yr.",
    "파일럿 -0.371 대비 개선했으나 HARD 2.95 와 거리가 크다.",
    "조건부(t-1 저변주도 27개월만) canonical PORT_t = +2.198, net_SR 1.318 — 4.3배 도약이나",
    "월 선택이 사후이고 n=27, 월 비연속으로 turnover 해석 불가. 자본 주장 불가.", sep = " "),
  pit_evidence = paste(
    "lag1 스트레스 t_NW +2.362 (base +1.994, 붕괴 없음) · 정정값 소급 주입(Panel B) 평균 IC -0.0045 하락(t -1.381)",
    "= 사후정보 누출 지문 부재 · 하네스 카나리아 IC 1.0000(look-ahead) / 0.0155(난수)로 측정기 생존 실증", sep = " "),
  boundary = paste(
    "★pre-2019 파싱 불가 실측: 2017-03~2018-12 1,199행 중 OK 29(2.4%), PARSER_ERROR 620 + UNZIP_FAIL 527.",
    "'DART 원문은 2008-01까지 존재'는 문서 존재 여부이지 **신호 생성 가능성이 아니다** —",
    "경계 주장을 할 때 존재/가용/파싱가능 세 층을 구분하지 않으면 지불 결정이 틀린다.", sep = " "),
  infra_defect_found = paste(
    ".cache/benchmark.parquet(08-03 08:36 재생성) BM_Close 가 2026-07-27 에 9325 → 1069 로 스케일 절단 →",
    "2026-07 홀딩월 -91.36%(정본 -23.63%). 두 소스 접합에 연속성 단언이 없다. 본 라운드는 pinned 정본",
    "라벨 오버라이드로 우회하고 수리는 분리 태스크로. 08-03 08:36 이후 이 파일을 소비한 산출물은 재검토 대상.", sep = " "),
  next_probe = list(
    list(id = "NP-1", priority = "P1",
         probe = "국면 조건부 소비를 **사전등록**으로 재판정: t-1 mega_spread <= 0 게이트를 사전 고정하고, 문턱은 단일값이 아니라 분포 q05(FQ-109)로. 판정 = 조건부 canonical PORT_t 와 무조건 대비 개선폭.",
         why = "본 라운드 최강 신호(격차 +0.134, 순열 p 0.008)가 사후 선택이라 확정 불가. 사전등록만이 이를 주장으로 바꾼다.",
         cost = "재크롤 0 — 기존 패널·그리드 재사용"),
    list(id = "NP-2", priority = "P1",
         probe = "메커니즘 반증 직접 시험: score 상위분위의 t+1~t+3 기관 순매수(A6_investor_flow_stock_daily) 가 하위분위 대비 증가하는가. 증가 없으면 'path' 기각 — 그러면 국면 의존은 다른 기전이다.",
         why = "alpha_package falsification 1번 항목이 미측정 상태다. 성과가 아닌 부수 관측으로 기전을 시험하는 유일한 항목.",
         cost = "investor_wide.parquet 재사용, 크롤 0"),
    list(id = "NP-3", priority = "P2",
         probe = "파서 조건부 게이트: 2010/2012/2014/2016/2017 각 30건 샘플 파싱 성공률 측정(150 호출). >=90% 이면 2015-2018 확장 지불, 미만이면 파서 수리 선행.",
         why = "잔여 구간 지불 결정의 전제가 '파싱 가능'인데 그 값이 pre-2019 에서 2.4% 로 실측됐다. 지불 전 저비용 확인이 필수.",
         cost = "150 호출 (전액 22,533 대비 0.7%)"),
    list(id = "NP-4", priority = "P2",
         probe = "소비면 순회 잔여: ②유니버스 필터(계약 신호 보유 종목만 후보로 제한한 뒤 기존 book 신호 적용)와 ⑥선별 라벨. FQ-126 과 병합 가능.",
         why = "MAX5 선례(랭킹 死·필터 生, ΔIR +0.169) — 랭킹 전이 벽에 막힌 재료가 필터면에서 살아난 실측이 있다. 단 base 는 production 실코드 + production_parity_verified 라벨 의무(WT-022 반전 실측).",
         cost = "패널 재사용")
  ),
  revival_conditions = list(
    "NP-1 사전등록 재판정에서 조건부 PORT_t 가 무조건 대비 유의 개선을 재현하면 → 오버레이/필터 lane 으로 승격 검토",
    "NP-2 에서 기관 후속 유입 경로가 기각되면 → 국면 의존을 다른 기전(예: 소형주 유동성 사이클)으로 재서술 후 재설계",
    "파서 성공률 >= 90% 확인 시 → 2015-2018 확장으로 n>=127 재측정",
    "mega-cap 집중도가 2024 이전 수준으로 정상화된 국면이 6개월 지속되면 → trailing 24개월 무조건 재측정"
  ),
  artifacts = c(file.path(OUTD, "fq125_stage1_results.json"),
                file.path(OUTD, "fq125_stage1_controls.json"),
                file.path(OUTD, "fq125_stage1_regime_robust.json"),
                file.path(OUTD, "gridx_vintage_compare.json"),
                file.path(OUTD, "fq125_stage1_chart.png"),
                file.path(STG, "alpha_validation.json"),
                file.path(MBX, "alpha_package.json"))
)
write_json(lc, file.path(LD, "l_code_WT_D20260803_008_FQ125_CONTRACT_REGIME_CONDITIONAL.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[emit] →", file.path(LD, "l_code_WT_D20260803_008_FQ125_CONTRACT_REGIME_CONDITIONAL.json"), "\n")
