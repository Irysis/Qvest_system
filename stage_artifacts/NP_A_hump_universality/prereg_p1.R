# =============================================================================
# prereg_p1.R — NP-A 사전등록 + 측정용 신호 패널 구축 (판정량 미산출)
#
#   질문: WT-D20260808_003 이 중립 Q01 에서 확립한 혹(hump) 분위 프로파일
#         (EW-유니버스 대비 [-3.81 +1.37 +3.05 +1.78 -2.41], post-2015) 이
#         Q01 고유인가, KR long-only 신호의 공통 형태인가.
#
#   ★ 이 스크립트는 act(수익)를 신호와 결합하지 않는다. 프로파일/갭을 계산하지 않는다.
#      사전등록 규칙 고정 + 신호 패널 구축 + 검정력 사전계산까지만.
#
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/prereg_p1.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p1] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260809L)

P0 <- readRDS(file.path(IN3, "p0_panels.rds"))
P1p<- readRDS(file.path(IN3, "prereg_p1.rds"))
E  <- P0$E[, .(Date, Ticker)]
N0 <- P0$N          # Date,Ticker,q01,Sector,Size,lsz,q01_n (부모 중립화 입력)
say("P0$N 컬럼: %s", paste(names(N0), collapse = ", "))
D  <- P1p$D         # Date,Ticker,q01,q01_n,act  (부모 판정패널 = 공통 프레임 A)
say("공통 프레임 A(P1$D) nrow=%d n_month=%d 월평균 %.1f종목", nrow(D), uniqueN(D$Date), D[,.N,by=Date][,mean(N)])

FDB_WANT <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
              "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O","M26_Revenue_Mom")
TUNED_WANT <- c("D03_EWMA","Q01_EB")
POP10 <- c(FDB_WANT, TUNED_WANT)

# =============================================================================
# 1. 신호 패널 구축 (C15 커넥터 경유 · Z_Score_Aligned = 방향정렬, C13 준수)
# =============================================================================
PANEL_F <- file.path(OUT, "signal_panel.rds")
if (file.exists(PANEL_F)) {
  SP <- readRDS(PANEL_F); say("신호 패널 캐시 재사용 nrow=%d", nrow(SP))
} else {
  SIG <- sort(unique(E$Date))
  say("=== 1. factor DB 8신호 로드 (%d개월, load_month_factors 경유) ===", length(SIG))
  acc <- vector("list", length(SIG)); asof <- character(length(SIG))
  for (i in seq_along(SIG)) {
    fm <- tryCatch(load_month_factors(SIG[i], coverage_min = 0.0, factor_names = FDB_WANT),
                   error = function(e) NULL)
    if (is.null(fm) || !nrow(fm)) next
    ad <- attr(fm, "factor_db_asof_date"); asof[i] <- as.character(ad)
    dt <- as.data.table(fm)[, .(Date = SIG[i], Ticker, Factor_Name, z = Z_Score_Aligned)]
    acc[[i]] <- dt
    if (i %% 50 == 0) say("  ... %d/%d (%s)", i, length(SIG), SIG[i])
  }
  FDB <- rbindlist(acc)
  # ★ as-of 무결성: 커넥터가 요청월 파일 부재로 이전월을 대체 로드하면 stale.
  #   요청일과 asof 가 다른 월을 기록해 둔다(사후 은폐 방지).
  mism <- data.table(Date = SIG, asof = asof)[asof != "" & asof != as.character(Date)]
  say("  factor DB 로드 완료 nrow=%d · asof≠요청일 월수 %d", nrow(FDB), nrow(mism))

  TU <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[
        Factor_Name %in% TUNED_WANT, .(Date = as.Date(Date), Ticker, Factor_Name, z = score)]
  say("  tuned 2신호 nrow=%d", nrow(TU))

  SP <- rbindlist(list(FDB, TU))
  SP <- merge(SP, E, by = c("Date","Ticker"))          # 적격집합으로 제한
  SP <- SP[is.finite(z)]
  attr(SP, "asof_mismatch") <- mism
  saveRDS(SP, PANEL_F)
  say("  적격집합 제한 후 신호 패널 nrow=%d", nrow(SP))
}
cov_tab <- SP[, .(rows = .N, n_month = uniqueN(Date), avg_names = .N/uniqueN(Date),
                  from = as.character(min(Date)), to = as.character(max(Date))), by = Factor_Name][order(Factor_Name)]
print(cov_tab)

# =============================================================================
# 2. 중립화 (섹터 + log(Size)) — 부모 precheck_p0.R 원문과 동일 절차
# =============================================================================
NEU_F <- file.path(OUT, "signal_panel_neutral.rds")
if (file.exists(NEU_F)) {
  SPN <- readRDS(NEU_F); say("중립 패널 캐시 재사용 nrow=%d", nrow(SPN))
} else {
  say("=== 2. 섹터+log(Size) 중립화 (부모 절차 원문) ===")
  CTL <- N0[, .(Date, Ticker, Sector, lsz)]
  W <- merge(SP, CTL, by = c("Date","Ticker"), all.x = TRUE)
  W[is.na(Sector), Sector := "UNKNOWN"]
  W[, zn := {
      ok <- is.finite(z) & is.finite(lsz)
      r <- rep(NA_real_, .N)
      if (sum(ok) >= 30L && uniqueN(Sector[ok]) >= 2L)
        r[ok] <- residuals(lm(z[ok] ~ lsz[ok] + factor(Sector[ok])))
      r }, by = .(Date, Factor_Name)]
  SPN <- W[, .(Date, Ticker, Factor_Name, z, zn)]
  saveRDS(SPN, NEU_F)
  say("  중립화 성공 %d / %d행", sum(is.finite(SPN$zn)), nrow(SPN))
}

# =============================================================================
# 3. 사전등록 (측정 전 고정) — 결과 열람 전에 기록된다
# =============================================================================
say("=== 3. 사전등록 규칙 고정 ===")

# 3a. 검정력 사전계산 — 관심 효과크기는 부모 승계값(재측정 아님)
#   부모 중립 Q01: 전표본 혹 깊이 q3-q5 = 2.2005 - 1.6456 = 0.555%/yr
#                   post-2015 혹 깊이 = -3.3456 - (-8.8078) = 5.462%/yr
eff_full_ann  <- 0.5549; eff_p15_ann <- 5.4622
n_full <- 295L; n_p15 <- 138L
pw <- list()
for (nm in c("full","post2015")) {
  n <- if (nm == "full") n_full else n_p15
  r_ext <- required_effect(n = n, t_threshold = 2.0, sd_monthly = SPREAD_SD_MONTHLY_25EW, design = "full")
  pw[[nm]] <- list(n = n,
    external_ref_sd_monthly = SPREAD_SD_MONTHLY_25EW,
    external_ref_source = "required_effect_size.R::SPREAD_SD_MONTHLY_25EW (top-25 EW 바스켓 쌍 월수익차 실측)",
    required_annual_pct_external = 100*r_ext$required_annual,
    inherited_effect_annual_pct = if (nm == "full") eff_full_ann else eff_p15_ann)
  say("  검정력(외부기준 sd=%.4f) n=%d → 필요 연 %+.2f%% vs 승계 효과 연 %+.2f%% ⇒ %s",
      SPREAD_SD_MONTHLY_25EW, n, 100*r_ext$required_annual,
      pw[[nm]]$inherited_effect_annual_pct,
      if (pw[[nm]]$inherited_effect_annual_pct >= 100*r_ext$required_annual) "개별신호 검정 가능" else "개별신호 검정 불가 → 형태 변경")
}
say("  ★ 외부(배포) 기준 바에서는 개별 신호의 갭 검정이 불가하다 —")
say("    ⇒ 사전등록 주판정을 '개별 유의성'이 아니라 (i) 형태 계수(count) + (ii) 신호간 평균 월계열(pooled)로 고정한다.")

PRE <- list(
  id = "NP-A", question = "혹(hump) 분위 프로파일이 Q01 고유인가 KR long-only 공통인가",
  attributed_to = "WT-D20260808_003 next_probe NP-A (신규 WT 아님)",
  registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  capital_claim = "없음 — 자본 자격 주장 금지",

  population = list(
    n_signals = 10L, signals = POP10,
    source = list(factor_db_via_load_month_factors = FDB_WANT,
                  tuned_panel_WT_D20260802_009 = TUNED_WANT),
    anchor_extra = "Q01_EB_NEU (부모의 정확한 참조 arm) — 계수 통계에는 미포함, 앵커로만 보고",
    rule = "사후에 신호/종목을 빼지 않는다. 커버리지 부족 월은 사전 문턱(월 적격 30종목)으로만 제외."),

  frames = list(
    A_common = "P1$D 행(부모 판정패널 = Q01 커버 stock-month). 전 신호 동일 stock-month → 사과-대-사과. **판정 프레임**",
    B_own    = "각 신호 자체 커버리지(적격집합 E 내). 사전등록 강건성 확인",
    disagreement_rule = "A/B 판정 불일치 시 공통형/고유 단정 금지 → 혼재로 강등하고 축 보고"),

  arms = list(
    raw_primary     = "as-loaded 방향정렬 z (배포 형태)",
    neutral_primary = "섹터+log(Size) 중립 (부모 혹이 관측된 형태)",
    rule = "두 arm 은 공동-주판정. 판정 규칙을 각각 적용하고 **일치할 때만** 공통형/고유 단정. 불일치 = 혼재 + 축 표기"),

  window = list(
    primary = "전표본 (295개월, 2001-12~2026-06)",
    inherited_replication = "post-2015 (부모 창을 전 신호에 **동일 고정** 적용 — 새 분할 아님, 승계 창 복제. 저검정력 라벨 의무)",
    era_axis = "연속 조건화만 — 월별 갭 계열 ~ 시간지수 회귀 (분할 금지)"),

  measurement = list(
    profile_fn = "run_selfadv_p8.R::prof() **원문 이식** (probe_p0.R 에서 최대편차 8.9e-15 로 재현 확인)",
    ew_relative = "profile - mean(profile) (등개수 5분위이므로 평균 = EW 유니버스 active)",
    gap = "gap_q5_q3 = 월별 (q5 - q3) 계열. 연환산 = 100*12*mean",
    top_vs_ew = "월별 (q5 - 5분위평균) 계열",
    shape_flags = list(
      hump_weak = "gap_q5_q3 < 0 (최상위 < 중간)",
      hump_strict = "argmax(profile) 이 내부분위 {2,3,4}",
      top_below_ew = "EW-상대 q5 < 0"),
    observation_unit = "MONTHLY (월별 횡단면 평균의 시계열) — 첫 출력에 실측 인쇄",
    nw_lag_rule = paste0("겹치는 창 함정 방지: 모든 판정 계열의 ACF r1 을 먼저 실측한다. ",
      "r1 <= 0.30 이면 lag-3 인용, r1 > 0.30 이면 lag-12 + stride-12 부분표본을 병기하고 **더 보수적인 값만 인용**. ",
      "부모 라운드가 겹치는 60m 창 계열(ACF r1 0.86~0.94)에 lag-3 을 얹어 |t| 를 2.5~3.0배 부풀린 전례."),
    inference_primary = "월별 갭 계열의 이동블록 부트스트랩(block=12, B=2000) 95% CI + 양측 p (자기상관 내성)",
    inference_secondary = "NW t (위 lag 규칙)"),

  primary_tests = list(
    P1_pooled = "월별로 가용 신호들의 gap_q5_q3 을 평균한 단일 계열 → 블록 부트스트랩 CI + NW t. 신호간 상관에 내성",
    P2_count  = "hump_weak 인 신호 수 / 10 (정확 이항 p vs 0.5). ★신호간 독립 위배 — 서술용, 단독 판정 근거 아님",
    P3_persig = "신호별 갭 + CI (개별 유의성은 외부기준 바에서 검정 불가 — 라벨 의무)"),

  decision_rule = list(
    common = "hump_weak >= 7/10 (>=2/3) AND P1_pooled 갭이 0 미만이며 부트스트랩 95% CI 가 0 을 배제 ⇒ 공통형",
    q01_specific = "hump_weak <= 3/10 (<=1/3) ⇒ Q01 고유. 벽 일반화 금지",
    mixed = "그 외(계수는 충족하나 pooled CI 가 0 포함 등) ⇒ 혼재. 무엇이 혹형/단조형을 가르는지 연속 조건화로 **탐색**(판정 아님, 사후 서사 금지)",
    tie_break = "raw arm 과 neutral arm 이 불일치하면 무조건 혼재로 강등"),

  conditioning_vars_for_mixed = c(
    "persistence = 신호 월간 rank 자기상관(회전율 역수)",
    "coverage = 적격집합 내 평균 커버리지",
    "family = fundamental / estimate_revision / price_based",
    "capacity = 최상위분위 평균 log(Size)"),
  conditioning_label = "n=10 신호 → 신호간 회귀는 서술적 탐색. 판정 근거 아님",

  power = pw,
  power_note = paste0("verdict_with_power 는 측정 후 호출하되 **외부 기준 계열**(SPREAD_SD_MONTHLY_25EW)을 넣는다. ",
    "반환 implied_t_threshold 를 반드시 확인하고 2.0~3.2 구간이면 INCONCLUSIVE_BAR_RESTATES_T = 정보 없음으로 취급한다. ",
    "arm 자신의 sd 를 넣은 값도 투명성 목적으로 병기하되 '재진술' 라벨을 붙인다."),

  forbidden = c("공분산/weight/사전 최적화", "제약 완화 제안(INV-7)", "자본 자격 주장",
                "결과 열람 후 모집단·분위 정의 변경", "rank-IC 단독으로 전이 예측", "부분표본 분할 판정"),
  metric_type = "canonical_screen / diag (실측 · proxy 손계산 없음)"
)
write_json(PRE, file.path(OUT, "preregistration.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
write_json(list(coverage = cov_tab), file.path(OUT, "panel_coverage.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 사전등록 기록 완료 → preregistration.json (판정량 미열람) ===")
