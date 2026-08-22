## WT-D20260822_002 · P3 — co-primary paired 판정 + 라벨 + 진단 배터리
##
## 사전등록: PREREG.json (P2 이전 봉인). 본 파일은 관문(P2 §9) **이후**에만 실행된다.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p3_verdict.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
OUT  <- "stage_artifacts/WT-D20260822_002"
SRC  <- "stage_artifacts/fq233_probe0_20260813"
P2 <- readRDS(file.path(OUT, "p2_arms.rds"))
RES <- P2$RES; SC <- P2$SC; ARMS <- P2$ARMS; GATE <- P2$GATE; DIV <- P2$DIV; sel <- P2$sel
MDE_THRESHOLD <- 3.0    # ★PREREG 사전고정 — 사후 조정 금지

cat("=== 1) arm 별 절대 성과 (metric_type = canonical_screen · basis 명시) ===\n")
tab <- rbindlist(lapply(ARMS, function(a) { r <- RES[[a]]
  data.table(arm = a, n = r$n_months, port_t_capw = r$portfolio_alpha_t_nw_lag3,
             ir_active = r$net_sr, alpha_ann = r$alpha_annualized,
             port_t_ew = tryCatch(r$diag_ew_universe$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_),
             turnover = r$turnover_annual) }))
print(tab)
cat("  basis: port_t_capw = bench_dt(.cache/benchmark.parquet 일별→월간) · port_t_ew = EW-유니버스 진단\n")

cat("\n=== 2) ★co-primary paired 판정 (NW lag-3, 양측 문턱 ±2.0) ===\n")
getpr <- function(a) RES[[a]]$period_returns[, .(date, ret_net, benchmark_ret)]
paired <- function(a, b) {
  m <- merge(getpr(a), getpr(b), by = "date", suffixes = c("_a","_b"))
  d  <- m$ret_net_a - m$ret_net_b                       # 벤치는 차분에서 상쇄 (basis 불변)
  da <- (m$ret_net_a - m$benchmark_ret_a) - (m$ret_net_b - m$benchmark_ret_b)
  list(n = nrow(m), mean_m = mean(d), t_nw3 = .nw_t_mean(d, lag = 3L),
       mean_active_m = mean(da), t_active_nw3 = .nw_t_mean(da, lag = 3L),
       sd_m = sd(d), ann_pct = 100 * mean(d) * 12, d = d, date = m$date)
}
CP <- list(A = paired("SEL_PEARSON", "SEL_RANK"), B = paired("SEL_MEANDEPTH", "SEL_RANK"))
AUX <- list(NEG = paired("NEG_MEDDEPTH","SEL_RANK"), INJ = paired("INJ_LOOKAHEAD_PEARSON","SEL_RANK"),
            LAG1 = paired("LAG1_PEARSON","SEL_RANK"))
pr1 <- function(nm, p) cat(sprintf("  %-34s n=%d  평균 %+.5f/월 (연 %+.3f%%p)  t_NW3 %+.4f  [active-diff t %+.4f]\n",
                                   nm, p$n, p$mean_m, p$ann_pct, p$t_nw3, p$t_active_nw3))
pr1("(A) SEL_PEARSON - SEL_RANK", CP$A); pr1("(B) SEL_MEANDEPTH - SEL_RANK", CP$B)
for (k in names(AUX)) pr1(sprintf("    [%s]", k), AUX[[k]])

cat("\n=== 3) 재현 검문 — (B) paired t 는 WT005 값(1.57062)을 복원해야 한다 ===\n")
cat(sprintf("  실측 %+.5f · 사전등록 %+.5f · Δ %+.6f ⇒ %s\n", CP$B$t_nw3, 1.57062, CP$B$t_nw3 - 1.57062,
            if (abs(CP$B$t_nw3 - 1.57062) <= 5e-4) "재현" else "★불일치"))

cat("\n=== 4) ★검정력 라벨 (PREREG 사전고정 규칙 — 문턱 사후조정 금지) ===\n")
cat("  ★바가 무엇을 재는지 신고(required_effect_size.R 규약): implied_t_threshold =\n")
cat("     MDE / se_arm — '이 바는 arm 자신의 se 기준 t 몇 짜리인가'. 문턱 근방이면 바 = t 검정 재진술.\n")
lab <- function(id, p) {
  g <- GATE[grepl(if (id=="A") "^SEL_PEARSON" else "^SEL_MEANDEPTH", contrast)]
  mde <- g$mde_annual_pct
  se_arm <- abs(p$mean_m) / abs(p$t_nw3)
  implied <- (mde/100/12) / se_arm
  powered <- mde <= MDE_THRESHOLD
  L <- if (abs(p$t_nw3) >= 2.0) { if (p$t_nw3 > 0) "SUPPORTED_SELECTION_STAT" else "INFERIOR_POWERED" }
       else if (powered) "NOT_SUPPORTED_POWERED" else "UNDERPOWERED_UNRESOLVED"
  cat(sprintf("  (%s) MDE 연 %.3f%%p (문턱 %.1f) · |t| %.4f · implied_t_threshold %.3f ⇒ %s\n",
              id, mde, MDE_THRESHOLD, abs(p$t_nw3), implied, L))
  if (L == "UNDERPOWERED_UNRESOLVED")
    cat(sprintf("      ⇒ 배제되는 것: 연 %.2f%%p 이상 효과. 미결로 남는 것: 연 %.1f~%.2f%%p 구간.\n",
                mde, MDE_THRESHOLD, mde))
  list(label = L, mde = mde, implied_t_threshold = implied, se_arm = se_arm)
}
LBL <- list(A = lab("A", CP$A), B = lab("B", CP$B))
cat(sprintf("\n  ★양성 대조(위반 주입) t = %+.4f — 같은 통계·같은 n 에서 문턱 크기 효과 탐지력 %s\n",
            AUX$INJ$t_nw3, if (abs(AUX$INJ$t_nw3) >= 2.0) "실증(장치 정상)" else "★미실증 — null 해석 봉인"))
cat(sprintf("  PIT 스트레스(LAG1) t = %+.4f (창을 한 칸 더 물림 — 붕괴 시 동월 누출 의심)\n", AUX$LAG1$t_nw3))

cat("\n=== 5) basis 불변성 (paired 설계에서 벤치가 상쇄되는가) ===\n")
for (id in c("A","B")) cat(sprintf("  (%s) total-diff t %+.5f vs active-diff t %+.5f · Δ %+.2e\n",
    id, CP[[id]]$t_nw3, CP[[id]]$t_active_nw3, CP[[id]]$t_nw3 - CP[[id]]$t_active_nw3))
cat("  ⇒ 두 값이 같으면 판정이 벤치 basis 논쟁과 독립임을 뜻한다(WT005 1.5706 vs 1.5709 대조).\n")

cat("\n=== 6) R2 부기간 분해 (KQ150 소급 투영 2010-02~2015-06 격리) ===\n")
sub <- function(p, from, to) { i <- p$date >= as.Date(from) & p$date <= as.Date(to)
  if (sum(i) < 24L) return(data.table(win=paste(from,to), n=sum(i), t=NA_real_, ann=NA_real_))
  data.table(win = paste(from, to), n = sum(i), t = .nw_t_mean(p$d[i], lag=3L), ann = 100*mean(p$d[i])*12) }
for (id in c("A","B")) { cat(sprintf("  (%s)\n", id))
  print(rbindlist(list(sub(CP[[id]], "2008-03-01","2015-06-01"), sub(CP[[id]], "2015-07-01","2026-07-01"),
                       sub(CP[[id]], "2010-02-01","2015-06-01")))) }

cat("\n=== 7) R3 상위 5개월 민감도 ===\n")
for (id in c("A","B")) { p <- CP[[id]]; o <- order(abs(p$d), decreasing = TRUE)[1:5]
  dd <- p$d[-o]
  cat(sprintf("  (%s) 전체 t %+.4f → |d| 상위5 제외 t %+.4f (n %d→%d)\n", id, p$t_nw3,
              .nw_t_mean(dd, lag=3L), p$n, length(dd))) }

cat("\n=== 8) 선별 자기-회전율 (mechanism.path 검증 가능 함의: (a) < (b) 여야 한다) ===\n")
self_to <- function(a) { s <- sel[[a]]; nm <- names(s)
  v <- vapply(2:length(nm), function(i) 1 - length(intersect(s[[nm[i]]], s[[nm[i-1]]]))/length(s[[nm[i]]]),
              numeric(1)); mean(v) }
for (a in c("SEL_RANK","SEL_PEARSON","SEL_MEANDEPTH","NEG_MEDDEPTH"))
  cat(sprintf("  %-16s 월별 선별집합 교체율 평균 %.4f\n", a, self_to(a)))

cat("\n=== 9) DSR 진단 (chain — HARD 아님) + MDD/Calmar ===\n")
for (a in c("SEL_RANK","SEL_PEARSON","SEL_MEANDEPTH")) { r <- RES[[a]]
  cat(sprintf("  %-16s net_sr(active IR) %+.4f · CAGR %s · MDD %s · calmar %s\n", a, r$net_sr,
      if (!is.null(r$cagr)) sprintf("%+.4f", r$cagr) else "n/a",
      if (!is.null(r$max_drawdown)) sprintf("%.4f", r$max_drawdown) else "n/a",
      if (!is.null(r$calmar)) sprintf("%.4f", r$calmar) else "n/a")) }
cat("  (사용 가능한 필드:", paste(names(RES$SEL_RANK), collapse=", "), ")\n")

saveRDS(list(CP = CP, AUX = AUX, LBL = LBL, tab = tab), file.path(OUT, "p3_verdict.rds"))
cat("\n[saved] p3_verdict.rds\n")
