#!/usr/bin/env Rscript
# =============================================================================
# p9_np5_redesigned.R — FQ-170 NP-5 재설계판: 위치-이동 밴드 (교차 교훈 반영)
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# 질문: 중립판(z_neutral, HUMP·기공개 argmax D5)은 밴드를 **그 위치**로 옮기면 사는가.
# 초안 폐기 사유: "밴드 내 상위 25" 는 밴드가 아니라 밴드 top edge 를 잰다(3ccb658c 함정 #1).
# 재설계 (교차 교훈 4종 전부 반영):
#   [교훈#1 회피] 밴드 **전체 EW** — 재선별 없음. 25종 제약 미준수 = 기전 셀이지 배포 셀 아님(라벨).
#   [교훈#2] 유효분위 위치 필드 — arm 별 선택 종목의 평균 백분위 실측 출력.
#   [교훈#3] 대조군 = base 아닌 **동일 폭 무작위 밴드**(위치 무작위, draw 100) — 밴드라는 행위
#            자체의 효과와 위치의 효과를 분리.
#   [교훈#6] 양성 대조 보존 — 같은 재설계 규칙으로 raw(argmax D8) D7~D9 전체 EW 가 먼저
#            재현돼야 본 검정 유효. 미재현이면 검사 무효 선언.
# arm:
#   P0 양성대조: Q01 raw D7~D9(60~90분위) 전체 EW vs raw top-25       — 재현 관문
#   B1 주검정  : z_neutral D4~D6(30~60분위) 전체 EW vs neutral top-25
#   R  무작위  : 폭 30%p 밴드를 [0,0.70] 시작점 균등 무작위 100 draw (재료별)
# 판정 (사전 고정):
#   유효 = P0 paired t >= 2.0 (미달 시 검사 무효 — B1 해석 금지)
#   B1 성립 = paired t >= 2.0 ∧ B1 효과 > 무작위 draw 분포 q95
#   B1 미달(유효한 검사에서) = "중립판은 위치를 맞춰도 안 삶" — 중립화가 소비 가치를 깎는다는 확정.
# metric_type = backtested_screen(계약 net) · 기전 셀(배포 아님) · capital_claim=false
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); OUT <- file.path(ROOT, "stage_artifacts/FQ170_claim_20260809")

## ── 세션-간 잠금: next_action 선갱신 (프로토콜) ──────────────────────
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
qi <- which(ids == "FQ-170")
na_cur <- as.character(Q$entries[[qi]]$next_action)[1]
if (!grepl("IN_PROGRESS ba4a1c30 NP-5재설계", na_cur)) {
  Q$entries[[qi]]$next_action <- paste0("[IN_PROGRESS ba4a1c30 NP-5재설계 ",
                                        format(Sys.time(), "%H:%M"), "] ", na_cur)
  write_frontier_queue(Q)
}

sink(file.path(OUT, "p9_np5.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bm_dt <- as.data.table(P$bench)[, .(Date = as.Date(Date), BM_Ret)]
X <- merge(B, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[0] 패널: %d행 %d개월\n", nrow(X), uniqueN(X$Date)))

prep <- function(scorecol) {
  D <- X[!is.na(get(scorecol))]
  D[, n_m := .N, by = Date]; D <- D[n_m >= 50]
  D[, pr := frank(get(scorecol), ties.method="first") / .N, by = Date]
  D
}
w_band <- function(D, lo, hi) D[pr > lo & pr <= hi][, .(Date, Ticker, w = 1, pr)]
w_top25 <- function(D, scorecol) D[, .SD[frank(-get(scorecol), ties.method="first") <= 25],
                                   by = Date][, .(Date, Ticker, w = 1, pr)]
ts_act <- function(bt) { tt <- NULL
  for (k in c("monthly","period_returns","series","port"))
    if (k %in% names(bt) && is.data.frame(bt[[k]])) { tt <- as.data.table(bt[[k]]); break }
  dc <- intersect(c("date","Date"), names(tt))[1]
  tt[, .(d_ = get(dc), a = ret_net - benchmark_ret)] }
run_bt <- function(wdt, id) weighted_screen_bt(wdt[, .(Date, Ticker, w)], ret, bm_dt, 15,
                                               run_id="FQ170_NP5r", strategy_id=id)
pair <- function(bX, bY) { M <- merge(ts_act(bX), ts_act(bY), by="d_", suffixes=c("X","Y"))
  d <- M$aY - M$aX; list(t=.nw_t_mean(d, lag=3L), yr=12*mean(d)) }
eff_pct <- function(wdt) mean(wdt$pr)   # 교훈#2: 유효분위 실측

cat("\n=== [P0] 양성 대조 재현 관문: raw D7~D9 전체 EW vs raw top-25 ===\n")
Dr <- prep("Q01_EB")
w_r_band <- w_band(Dr, 0.60, 0.90); w_r_top <- w_top25(Dr, "Q01_EB")
cat(sprintf("  유효분위: band %.3f (설계 0.75 근방) · top25 %.3f | band 월평균 %d 종\n",
            eff_pct(w_r_band), eff_pct(w_r_top), as.integer(nrow(w_r_band)/uniqueN(w_r_band$Date))))
p0 <- pair(run_bt(w_r_top, "raw_top25"), run_bt(w_r_band, "raw_band_full"))
cat(sprintf("  paired band−top25: %+.2f%%p/yr  t_NW3=%+.3f\n", 100*p0$yr, p0$t))
valid <- p0$t >= 2.0
cat(sprintf("  관문: %s\n", ifelse(valid, "재현 — 검사 유효", "미재현 — ★검사 무효, B1 해석 금지")))

R <- list(p0_positive_control = c(p0, list(valid = valid)))
if (valid) {
  cat("\n=== [B1] 주검정: z_neutral D4~D6 전체 EW vs neutral top-25 ===\n")
  Dn <- prep("z_neutral")
  w_n_band <- w_band(Dn, 0.30, 0.60); w_n_top <- w_top25(Dn, "z_neutral")
  cat(sprintf("  유효분위: band %.3f (설계 0.45 근방) · top25 %.3f | band 월평균 %d 종\n",
              eff_pct(w_n_band), eff_pct(w_n_top), as.integer(nrow(w_n_band)/uniqueN(w_n_band$Date))))
  bt_n_top <- run_bt(w_n_top, "neu_top25")
  p1 <- pair(bt_n_top, run_bt(w_n_band, "neu_band_full"))
  cat(sprintf("  paired band−top25: %+.2f%%p/yr  t_NW3=%+.3f\n", 100*p1$yr, p1$t))

  cat("\n=== [R] 동일 폭 무작위 밴드 대조 (draw=100, 교훈#3·#4) ===\n")
  set.seed(20260809)
  draws <- replicate(100, {
    lo <- runif(1, 0, 0.70)
    pr_ <- pair(bt_n_top, run_bt(w_band(Dn, lo, lo + 0.30), "neu_rand"))
    pr_$yr
  })
  q95 <- quantile(draws, .95)
  cat(sprintf("  무작위 밴드 효과 분포: mean %+.2f%%p  q95 %+.2f%%p  max %+.2f%%p  vs B1 %+.2f%%p\n",
              100*mean(draws), 100*q95, 100*max(draws), 100*p1$yr))
  b1_ok <- p1$t >= 2.0 && p1$yr > q95
  cat(sprintf("\n=== [판정] B1 t=%+.3f(%s) ∧ vs무작위 q95 %s → %s ===\n",
              p1$t, ifelse(p1$t>=2,"통과","미달"), ifelse(p1$yr>q95,"초과","이내"),
              if (b1_ok) "LOCATION_MATCHED_CONFIRMED"
              else "NEUTRAL_DEAD_EVEN_AT_HUMP — 중립화가 소비 가치를 깎는다는 확정"))
  R$b1 <- c(p1, list(rand_q95 = as.numeric(q95), rand_mean = mean(draws), pass = b1_ok))
}
R$meta <- list(metric_type="backtested_screen", cell_type="mechanism_not_deployment",
               capital_claim=FALSE, prereg="스크립트 헤더 — 교차 교훈 #1#2#3#6 반영")
write_json(R, file.path(OUT, "p9_np5.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
