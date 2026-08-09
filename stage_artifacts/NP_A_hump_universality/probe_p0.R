# =============================================================================
# probe_p0.R — NP-A 착수 전 사전 확인 (측정 아님 · 사전등록 전)
#   목적 3가지만:
#     (1) 입력 형태 실측 (행수·관측단위·범위)  — 가정 금지 규약
#     (2) 모집단 10 신호가 실제로 로드되는가 + 커버리지/개월수 (사후 제외 방지: 여기서 확정)
#     (3) 부모 프로파일 함수 재사용 시 Q01 숫자가 **비트 단위로 재현**되는가 (정의 갈림 방지)
#   ★ 이 스크립트는 판정량(q5-q3 gap)을 계산하지 않는다. 사전등록 전 본판정 열람 방지.
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/probe_p0.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p0] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/required_effect_size.R")

RES <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
            purpose = "NP-A precheck (no verdict quantity computed)")

# ── 0. 입력 형태 실측 ────────────────────────────────────────────────────────
shape <- function(d, nm, datecol = "Date") {
  d <- as.data.table(d)
  ud <- sort(unique(as.Date(d[[datecol]])))
  gap <- if (length(ud) > 2) median(as.numeric(diff(ud))) else NA_real_
  unit <- if (is.na(gap)) "UNKNOWN" else if (gap <= 5) "DAILY" else if (gap <= 45) "MONTHLY" else "LOWER"
  say("INPUT %-26s nrow=%9d 관측단위=%s(간격중앙 %.1f일) n_date=%d 범위 %s~%s",
      nm, nrow(d), unit, gap, length(ud), min(ud), max(ud))
  list(nrow = nrow(d), unit = unit, gap_median_days = gap, n_date = length(ud),
       from = as.character(min(ud)), to = as.character(max(ud)))
}

P0 <- readRDS(file.path(IN3, "p0_panels.rds"))
P1 <- readRDS(file.path(IN3, "prereg_p1.rds"))
sh <- list()
sh$E          <- shape(P0$E, "P0$E (적격집합)")
sh$returns_dt <- shape(P0$returns_dt, "P0$returns_dt (Ret_1m)")
sh$bench_dt   <- shape(P0$bench_dt, "P0$bench_dt (BM_Ret)")
sh$D_prereg   <- shape(P1$D, "P1$D (부모 판정패널)")
say("P1$D 컬럼: %s", paste(names(P1$D), collapse = ", "))
RES$input_shapes <- sh

# ── 1. 부모 프로파일 함수 원문 재사용 (재구현 금지) ─────────────────────────
#   run_selfadv_p8.R 의 prof() 를 문자 그대로 옮긴다. act = ret - BM (P1$D 승계).
prof_parent <- function(X, zc, win) {
  d <- if (win == "full") X else X[Date >= as.Date("2015-01-01")]
  d <- d[is.finite(get(zc)) & is.finite(act)]
  s <- d[, { qr <- frank(get(zc))/.N
    .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
      q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8])) }, by = Date]
  qm <- 100*12*c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
  list(quintile_ann_pct = qm, n_month = nrow(s), series = s)
}

D <- copy(P1$D)
rep_full <- prof_parent(D, "q01_n", "full")
rep_p15  <- prof_parent(D, "q01_n", "post2015")
gold <- fromJSON(file.path(IN3, "selfadv_p8.json"))
g_full <- gold$profile$q01_n_full$quintile_ann_pct
g_p15  <- gold$profile$q01_n_post2015$quintile_ann_pct
d_full <- max(abs(rep_full$quintile_ann_pct - g_full))
d_p15  <- max(abs(rep_p15$quintile_ann_pct  - g_p15))
say("재현 검증 q01_n full     : 재현 [%s]", paste(sprintf("%+7.4f", rep_full$quintile_ann_pct), collapse=" "))
say("재현 검증 q01_n full     : 정본 [%s]  최대편차 %.3e", paste(sprintf("%+7.4f", g_full), collapse=" "), d_full)
say("재현 검증 q01_n post2015 : 재현 [%s]", paste(sprintf("%+7.4f", rep_p15$quintile_ann_pct), collapse=" "))
say("재현 검증 q01_n post2015 : 정본 [%s]  최대편차 %.3e", paste(sprintf("%+7.4f", g_p15), collapse=" "), d_p15)
stopifnot(d_full < 1e-9, d_p15 < 1e-9)   # 정의가 갈리면 여기서 멈춘다
say("★ 부모 prof() 원문 재사용 확인 — 최대편차 %.3e (문턱 1e-9)", max(d_full, d_p15))
RES$parent_reproduction <- list(max_abs_dev_full = d_full, max_abs_dev_post2015 = d_p15,
                                threshold = 1e-9, passed = TRUE,
                                note = "run_selfadv_p8.R::prof() 원문 이식 — 재구현 아님")

# ── 1b. 계측 생존(양성 대조): 0 을 결론으로 읽지 않기 위한 사전 확인 ────────
#   부모 값이 있는 셀에서 EW-상대 프로파일이 실제로 프롬프트의 혹 벡터를 재생하는가
ew_rel <- function(q) q - mean(q)
hump_gold <- ew_rel(g_p15)
say("양성대조: EW-상대 post2015 중립 Q01 = [%s]  (프롬프트 승계값 [-3.81 +1.37 +3.05 +1.78 -2.41])",
    paste(sprintf("%+.2f", hump_gold), collapse = " "))
RES$positive_control <- list(ew_relative_q01_n_post2015 = hump_gold,
  matches_handoff = max(abs(hump_gold - c(-3.81, 1.37, 3.05, 1.78, -2.41))) < 0.01)
stopifnot(RES$positive_control$matches_handoff)

# ── 2. 모집단 10 신호 로드 가능성 (사후 제외 방지 — 여기서 확정) ────────────
say("=== 2. 모집단 신호 로드 가능성 (C15 커넥터 경유) ===")
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
tuned_have <- sort(unique(TUNED$Factor_Name))
say("tuned_panel 보유: %s", paste(tuned_have, collapse = ", "))

FDB_WANT <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
              "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O","M26_Revenue_Mom")
SIG <- sort(unique(P0$E$Date))
say("신호일 그리드: %d개월 %s~%s", length(SIG), min(SIG), max(SIG))

probe_dates <- SIG[round(seq(1, length(SIG), length.out = 6))]
probe <- list()
for (dd in as.character(probe_dates)) {
  fm <- tryCatch(load_month_factors(as.Date(dd), coverage_min = 0.0, factor_names = FDB_WANT),
                 error = function(e) { say("  load 실패 %s: %s", dd, conditionMessage(e)); NULL })
  if (is.null(fm)) next
  cnt <- as.data.table(fm)[, .N, by = Factor_Name]
  probe[[dd]] <- setNames(as.list(cnt$N), cnt$Factor_Name)
  say("  %s asof=%s  %s", dd, as.character(attr(fm, "factor_db_asof_date")),
      paste(sprintf("%s=%d", cnt$Factor_Name, cnt$N), collapse = " "))
}
RES$fdb_probe <- probe
found <- unique(unlist(lapply(probe, names)))
missing <- setdiff(FDB_WANT, found)
say("factor DB 에서 확인된 신호: %s", paste(sort(found), collapse = ", "))
if (length(missing)) say("★ 미확인: %s — 이름 재확인 필요 (사후 제외 아님)", paste(missing, collapse = ", "))
RES$fdb_found <- sort(found); RES$fdb_missing <- missing

write_json(RES, file.path(OUT, "probe_p0.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== probe 완료 → probe_p0.json ===")
