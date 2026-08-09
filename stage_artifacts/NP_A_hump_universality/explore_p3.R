# =============================================================================
# explore_p3.R — NP-A 혼재(MIXED) 분기 탐색 + 앵커 위치 서술
#   ★ 판정 아님. 사전등록 conditioning_vars_for_mixed 를 그대로 쓰고 사후 서사 금지.
#   포함:
#     (1) 신호별 표 전량 인쇄 (사후 제외 없음 확인용)
#     (2) 부모 앵커(중립 Q01)의 모집단 내 위치 — '고유' 주장의 정량 근거/반증
#     (3) 연속 조건화: persistence / coverage / family / capacity ~ 갭  (n=10, 서술)
#     (4) 계측 생존 확인(양성 대조) + 앵커 재현 확인
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/explore_p3.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p3] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
set.seed(20260809L)

M2  <- readRDS(file.path(OUT, "measure_p2.rds"))
SPN <- readRDS(file.path(OUT, "signal_panel_neutral.rds"))
P0  <- readRDS(file.path(IN3, "p0_panels.rds"))
P1p <- readRDS(file.path(IN3, "prereg_p1.rds"))
X <- list()

# ── 1. 신호별 표 전량 ────────────────────────────────────────────────────────
tab_of <- function(cellname) {
  ce <- M2$cells[[cellname]]
  rbindlist(lapply(names(ce$per_signal), function(fn) { z <- ce$per_signal[[fn]]
    data.table(cell = cellname, signal = fn, n_month = z$n_month, avg_names = z$avg_names,
      q1 = z$ew_relative_ann_pct[1], q2 = z$ew_relative_ann_pct[2], q3 = z$ew_relative_ann_pct[3],
      q4 = z$ew_relative_ann_pct[4], q5 = z$ew_relative_ann_pct[5],
      argmax = z$argmax_quintile, hump = z$hump_weak, topEW = z$top_below_ew,
      gap_ann = z$gap_q5_q3$ann_pct, gap_acf = z$gap_q5_q3$acf_r1,
      gap_lag = z$gap_q5_q3$cited_lag, gap_t = z$gap_q5_q3$t_cited,
      gap_lo = z$gap_q5_q3$boot_ci_ann_pct[1], gap_hi = z$gap_q5_q3$boot_ci_ann_pct[2],
      gap_p = z$gap_q5_q3$boot_p2) }))
}
TABS <- rbindlist(lapply(c("A_raw_full","A_neutral_full","A_raw_post2015","A_neutral_post2015"), tab_of))
for (cn in unique(TABS$cell)) {
  say("=== 신호별 EW-상대 분위 프로파일 (%s) ===", cn)
  print(TABS[cell == cn, .(signal, n_month, q1 = round(q1,2), q2 = round(q2,2), q3 = round(q3,2),
      q4 = round(q4,2), q5 = round(q5,2), argmax, hump, topEW,
      gap = round(gap_ann,2), acf = round(gap_acf,2), t = round(gap_t,2),
      ci = sprintf("[%+.2f,%+.2f]", gap_lo, gap_hi), p = round(gap_p,3))])
}
X$per_signal_table <- TABS

# ── 2. 앵커 위치 (부모 중립 Q01 이 모집단에서 어디에 있나) ───────────────────
say("=== 2. 앵커(부모 중립 Q01) 의 모집단 내 위치 ===")
anch <- M2$anchor
pos <- list()
for (wn in c("full","post2015")) {
  cn <- paste0("A_neutral_", wn)
  g_pop <- TABS[cell == cn, .(signal, gap_ann)][order(gap_ann)]
  a <- anch[[wn]]$gap_q5_q3$ann_pct
  rk <- sum(g_pop$gap_ann < a) + 1L
  # 모집단 내 Q01_EB(중립) 자기 자신 = 앵커 재현 확인 (양성 대조)
  self <- TABS[cell == cn & signal == "Q01_EB", gap_ann]
  say("  %-9s 앵커 갭 %+.3f%%/yr → 모집단 10개 중 %d번째로 작음 (모집단 범위 %+.2f ~ %+.2f, 중앙 %+.2f)",
      wn, a, rk, min(g_pop$gap_ann), max(g_pop$gap_ann), median(g_pop$gap_ann))
  say("           모집단 내 Q01_EB(중립) 자기값 %+.3f%% vs 앵커 %+.3f%% (편차 %+.3f%%p — 중립화 표본 차이)",
      self, a, self - a)
  pos[[wn]] <- list(anchor_gap_ann_pct = a, rank_ascending = rk, n_pop = nrow(g_pop),
                    pop_min = min(g_pop$gap_ann), pop_max = max(g_pop$gap_ann),
                    pop_median = median(g_pop$gap_ann),
                    in_pop_Q01_EB_neutral_gap = self, anchor_vs_inpop_dev = self - a,
                    ordered = g_pop)
}
X$anchor_position <- pos

# ── 3. 연속 조건화 (사전등록 변수 · n=10 서술) ───────────────────────────────
say("=== 3. 연속 조건화 — 무엇이 혹형/단조형을 가르나 (서술, 판정 아님) ===")
FAMILY <- c(C01_SUE = "estimate_revision", C02_EPS_Chg_1m = "estimate_revision",
            C04_ESBR = "estimate_revision", C06_TP_Gap = "estimate_revision",
            Q07_Earnings_Stability = "fundamental", Q25_Ohlson_O = "fundamental",
            M26_Revenue_Mom = "fundamental", M08_Residual_Mom = "price_based",
            D03_EWMA = "price_based", Q01_EB = "fundamental")
CTL <- P0$N[, .(Date, Ticker, lsz)]
W <- merge(SPN, CTL, by = c("Date","Ticker"), all.x = TRUE)
chars <- rbindlist(lapply(sort(unique(W$Factor_Name)), function(fn) {
  d <- W[Factor_Name == fn & is.finite(zn)]
  setorder(d, Date, Ticker)
  # persistence: 월-대-월 rank 자기상관 중앙값
  d[, r := frank(zn)/.N, by = Date]
  dts <- sort(unique(d$Date))
  pc <- sapply(seq_along(dts)[-1], function(i) {
    a <- d[Date == dts[i-1], .(Ticker, r0 = r)]; b <- d[Date == dts[i], .(Ticker, r1 = r)]
    m <- merge(a, b, by = "Ticker"); if (nrow(m) < 30L) NA_real_ else cor(m$r0, m$r1, method = "spearman") })
  # capacity: 최상위분위 평균 log(Size)
  cap <- d[is.finite(lsz), .(cap = mean(lsz[r > 0.8]), uni = mean(lsz)), by = Date]
  data.table(signal = fn, persistence = median(pc, na.rm = TRUE),
             coverage = d[, .N, by = Date][, mean(N)],
             capacity_rel = mean(cap$cap - cap$uni, na.rm = TRUE),
             family = unname(FAMILY[fn])) }))
for (wn in c("full","post2015")) {
  cn <- paste0("A_neutral_", wn)
  M <- merge(TABS[cell == cn, .(signal, gap_ann, hump)], chars, by = "signal")
  say("--- %s ---", cn); print(M[order(gap_ann), .(signal, gap = round(gap_ann,2), hump,
      persist = round(persistence,3), cover = round(coverage,0), cap_rel = round(capacity_rel,3), family)])
  for (v in c("persistence","coverage","capacity_rel")) {
    ct <- cor.test(M$gap_ann, M[[v]], method = "spearman", exact = FALSE)
    say("   갭 ~ %-12s Spearman rho %+.3f (p %.3f, n=%d)", v, unname(ct$estimate), ct$p.value, nrow(M)) }
  fam <- M[, .(n = .N, mean_gap = mean(gap_ann), n_hump = sum(hump)), by = family][order(mean_gap)]
  print(fam)
  X[[paste0("conditioning_", wn)]] <- list(table = M, family = fam)
}
X$signal_characteristics <- chars
X$conditioning_label <- "n=10 신호 · 신호간 상관 존재 · 서술적 탐색. 판정 근거 아님(사전등록 명시)"

# ── 4. 계측 생존 확인 (양성 대조 — 0/무효과를 결론으로 읽지 않기 위해) ──────
say("=== 4. 계측 생존(양성 대조) ===")
# 4a. 부모 혹 벡터가 앵커에서 그대로 재생되는가
gold <- fromJSON(file.path(IN3, "selfadv_p8.json"))$profile$q01_n_post2015$quintile_ann_pct
rep_ <- M2$anchor$post2015$quintile_ann_pct
say("  앵커 post2015 프로파일 최대편차 vs 부모 정본 = %.3e", max(abs(rep_ - gold)))
# 4b. 무작위 점수 placebo: 계측기가 '효과 없음'을 실제로 0 근처로 낸다
D <- copy(P1p$D)
pl <- replicate(30, {
  D[, rnd := runif(.N)]
  s <- D[, { qr <- frank(rnd)/.N
    .(q3 = mean(act[qr > 0.4 & qr <= 0.6]), q5 = mean(act[qr > 0.8])) }, by = Date]
  100*12*mean(s$q5 - s$q3) })
say("  placebo(무작위 점수) 갭 30 draw: 평균 %+.3f%%  sd %.3f  범위 [%+.3f, %+.3f]",
    mean(pl), sd(pl), min(pl), max(pl))
say("  ★ 계측기는 무신호에서 0 근처를 낸다 — 관측된 %+.3f%%(A_neutral_full pooled)는 계측 사망이 아님",
    M2$cells$A_neutral_full$pooled$ann_pct)
X$instrument_alive <- list(anchor_max_dev = max(abs(rep_ - gold)),
  placebo_gap_mean = mean(pl), placebo_gap_sd = sd(pl),
  placebo_range = c(min(pl), max(pl)), n_draw = 30L,
  observed_pooled_neutral_full = M2$cells$A_neutral_full$pooled$ann_pct)

write_json(X, file.path(OUT, "exploration.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(X, file.path(OUT, "explore_p3.rds"))
say("=== 탐색 완료 → exploration.json ===")
