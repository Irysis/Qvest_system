# =============================================================================
# selfadv_p6.R — Self-Adversarial Challenge (AX-008 3-source 중 1) — 산문 아닌 코드로 해소
#
#  SA-1 [ACCEPT] 계수(hump 개수)가 우연과 구별되는가? → **무작위 점수 placebo 로 계수의
#        귀무분포를 실측**한다. 구별 불가면 계수 규칙 단독 인용 금지로 강등한다.
#  SA-2 [ACCEPT] 조율자 규칙은 book 7종 계수만 본다. 크기 축(book-7 pooled 월계열)이
#        같은 방향을 가리키는지 별도 측정 — 계수와 크기가 갈리면 그대로 보고한다.
#  SA-3 [ACCEPT] Z_Score_Aligned 의 **방향 뒤집힘**이 표본 내에 있으면 '최상위 분위'의
#        의미가 시간에 따라 바뀐다 → 형태 주장 자체가 무너진다. 신호별 방향 전환 횟수 실측.
#  SA-4 [ACCEPT] 전표본↔승계창 불일치(raw arm) — 승계창이 저검정력이라는 사전 라벨이
#        사후 변명이 아님을 보이기 위해, 승계창 계수의 placebo 귀무분포도 함께 낸다.
#  SA-5 [진단] 검정 수 집계.
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/selfadv_p6.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a sa] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
set.seed(20260809L)

SPN <- readRDS(file.path(OUT, "signal_panel_neutral.rds"))
P0  <- readRDS(file.path(IN3, "p0_panels.rds")); P1p <- readRDS(file.path(IN3, "prereg_p1.rds"))
C5  <- readRDS(file.path(OUT, "correct_p5.rds"))
D <- copy(P1p$D); ACT_A <- D[, .(Date, Ticker, act)]
BOOK7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
           "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
S <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; f <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
prof2 <- function(X, zc, ties = "random") X[, { qr <- frank(get(zc), ties.method = ties)/.N
  .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
    q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8]), nn = .N) }, by = Date]

# ── SA-1/SA-4: 계수의 귀무분포 (무작위 점수 7개를 book-7 과 동일 창·프레임에) ──
say("=== SA-1/4: hump 계수의 귀무분포 — 무작위 점수 7종, 500 draw ===")
null_count <- function(cut, B = 500L) {
  Xw <- ACT_A[Date >= cut]
  sapply(seq_len(B), function(b) {
    sum(replicate(7L, {
      Xw[, rnd := runif(.N)]
      s <- prof2(Xw, "rnd")
      q <- c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
      q[5] < q[3] })) }) }
nc_full <- null_count(as.Date("1900-01-01")); nc_p15 <- null_count(as.Date("2015-01-01"))
obs_full_raw <- C5$cells[["tiebreak|A|raw|full"]];      obs_full_neu <- C5$cells[["tiebreak|A|neutral|full"]]
cnt7 <- function(ce) sum(sapply(ce$per_signal[intersect(BOOK7, names(ce$per_signal))], function(z) isTRUE(z$hump_weak)))
o <- list(full_raw = cnt7(obs_full_raw), full_neu = cnt7(obs_full_neu),
          p15_raw = cnt7(C5$cells[["tiebreak|A|raw|post2015"]]), p15_neu = cnt7(C5$cells[["tiebreak|A|neutral|post2015"]]))
say("  귀무(전표본): 평균 %.2f sd %.2f · 5~95%% [%d, %d]", mean(nc_full), sd(nc_full),
    quantile(nc_full, .05, names=FALSE), quantile(nc_full, .95, names=FALSE))
say("  귀무(post2015): 평균 %.2f sd %.2f · 5~95%% [%d, %d]", mean(nc_p15), sd(nc_p15),
    quantile(nc_p15, .05, names=FALSE), quantile(nc_p15, .95, names=FALSE))
pv <- function(obs, nul, lower) if (lower) mean(nul <= obs) else mean(nul >= obs)
for (k in names(o)) {
  nul <- if (grepl("full", k)) nc_full else nc_p15
  say("  관측 %-9s = %d/7 → 귀무 대비 단측 p(더 극단) = %.3f(혹 방향) / %.3f(단조 방향)",
      k, o[[k]], pv(o[[k]], nul, FALSE), pv(o[[k]], nul, TRUE)) }
S$SA1_count_null <- list(observed = o,
  null_full = list(mean = mean(nc_full), sd = sd(nc_full), q05 = quantile(nc_full,.05,names=FALSE), q95 = quantile(nc_full,.95,names=FALSE)),
  null_post2015 = list(mean = mean(nc_p15), sd = sd(nc_p15), q05 = quantile(nc_p15,.05,names=FALSE), q95 = quantile(nc_p15,.95,names=FALSE)),
  p_hump_side = sapply(names(o), function(k) pv(o[[k]], if (grepl("full",k)) nc_full else nc_p15, FALSE)),
  p_monotone_side = sapply(names(o), function(k) pv(o[[k]], if (grepl("full",k)) nc_full else nc_p15, TRUE)),
  n_draw = 500L,
  verdict = "아래 해석 필드 참조 — 계수가 귀무 5~95%% 안이면 계수 규칙 단독 인용 금지")
S$SA1_interpretation <- sapply(names(o), function(k) {
  nul <- if (grepl("full", k)) nc_full else nc_p15
  if (o[[k]] >= quantile(nul,.95,names=FALSE) || o[[k]] <= quantile(nul,.05,names=FALSE))
    "OUTSIDE_NULL_90" else "INSIDE_NULL_90_계수_단독_인용_금지" })

# ── SA-2: book-7 크기 축 (pooled 월계열) ────────────────────────────────────
say("=== SA-2: book-7 크기 축 — pooled 갭 월계열 (계수와 방향이 같은가) ===")
pooled7 <- function(arm, cut) {
  zc <- if (arm == "raw") "z" else "zn"
  gl <- rbindlist(lapply(BOOK7, function(fn) {
    X <- merge(SPN[Factor_Name == fn, .(Date, Ticker, z, zn)], ACT_A, by = c("Date","Ticker"))
    X <- X[Date >= cut & is.finite(get(zc)) & is.finite(act)]
    s <- prof2(X, zc); data.table(Date = s$Date, fn = fn, g = s$q5 - s$q3) }))
  P <- gl[, .(g = mean(g)), by = Date][order(Date)]
  list(n = nrow(P), ann_pct = 100*12*mean(P$g), acf_r1 = as.numeric(acf(P$g, lag.max=1, plot=FALSE)$acf[2]),
       t_nw3 = nw_t(P$g, 3L), t_nw12 = nw_t(P$g, 12L)) }
p7 <- list()
for (arm in c("raw","neutral")) for (wn in c("full","post2015")) {
  r <- pooled7(arm, if (wn=="full") as.Date("1900-01-01") else as.Date("2015-01-01"))
  p7[[paste(arm, wn, sep="|")]] <- r
  say("  book-7 pooled %-7s %-9s 연 %+.3f%% · ACF %+.2f · NW t(lag3) %+.2f (lag12 %+.2f) n=%d",
      arm, wn, r$ann_pct, r$acf_r1, r$t_nw3, r$t_nw12, r$n) }
S$SA2_book7_pooled <- p7

# ── SA-3: 방향 정렬 뒤집힘 census ───────────────────────────────────────────
say("=== SA-3: Z_Score_Aligned 방향 전환 census (전환 있으면 '최상위 분위' 의미가 변한다) ===")
SIGD <- sort(unique(P0$E$Date))
probe <- SIGD[seq(1, length(SIGD), by = 6)]   # 6개월 간격 표본 (49개월)
FDB8 <- setdiff(unique(SPN$Factor_Name), c("D03_EWMA","Q01_EB"))
ref <- NULL; flips <- list()
for (dd in probe) {
  fm <- tryCatch(load_month_factors(dd, coverage_min = 0.0, factor_names = FDB8), error = function(e) NULL)
  if (is.null(fm)) next
  raw <- tryCatch(as.data.table(arrow::read_parquet(
      file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", format(dd, "%Y%m"))),
      col_select = c("Ticker","Factor_Name","Z_Score")))[Factor_Name %in% FDB8], error = function(e) NULL)
  if (is.null(raw)) next
  m <- merge(as.data.table(fm), raw, by = c("Ticker","Factor_Name"))
  sg <- m[, .(sgn = sign(cor(Z_Score_Aligned, Z_Score, method = "spearman"))), by = Factor_Name]
  sg[, Date := dd]; flips[[as.character(dd)]] <- sg
}
FL <- rbindlist(flips)
fl_tab <- FL[, .(n_probe = .N, n_negative_alignment = sum(sgn < 0),
                 n_switch = sum(diff(sgn) != 0)), by = Factor_Name][order(-n_switch)]
print(fl_tab)
say("  ★ 방향 전환이 있는 신호: %s",
    if (nrow(fl_tab[n_switch > 0])) paste(fl_tab[n_switch > 0]$Factor_Name, collapse=", ") else "없음")
S$SA3_direction_flips <- list(table = fl_tab, n_probe_months = uniqueN(FL$Date),
  note = "Z_Score_Aligned vs 원 Z_Score 의 월별 Spearman 부호. 전환 = 최상위분위의 의미 변화 위험")

# ── SA-5: 검정 수 ───────────────────────────────────────────────────────────
S$SA5_test_count <- list(cells = 16L, per_signal_gap_tests = 160L, pooled_tests = 16L,
  book7_verdicts = 16L, conditioning_tests = 6L, null_simulations = 2L,
  prereg_primary = 1L,
  note = paste0("사전등록 주판정 = 전표본 A프레임 1건(조율자 축소 후 book-7 계수). ",
    "나머지는 강건성(수리 2종 × 프레임 2 × arm 2 × 창 2)·서술. ",
    "개별 신호 갭의 최대 |t| 를 단독 인용하지 않는다 — 계수/크기 두 축의 **일치**만 인용."))
say("=== SA 검정 수: 셀 16 · 신호별 갭 160 · 사전등록 주판정 1 ===")

write_json(S, file.path(OUT, "selfadv_p6.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(S, file.path(OUT, "selfadv_p6.rds"))
say("=== Self-Adversarial 재측정 완료 → selfadv_p6.json ===")
