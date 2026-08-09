## s2 — FQ-212: 완성 전략 40종(유효 독립)의 book-marginal 측정
## 표적: **출발 IR 0.7+**. 팩터DB 최고 0.576 · 계약 0.758(유일).
## ★규율: 창 정합 · verdict_ci(점추정 금지) · subsample_null 게이트 · 전 재료 보고(argmax 금지)
## ★주의: 이 풀에는 **PG2 자신과 그 파생**이 섞여 있다(STR_1715/1716, pg2_forensics).
##   자기 자신을 슬리브로 넣으면 ΔIR 0 이 나오므로 상관 1.0 근처는 **양성 대조**로 표시한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }

SER <- INV$ser; KEEP <- INV$keep; NMS <- INV$names
say("=== 대상 %d계열 (유효 독립) ===", length(KEEP))
say("  %-30s %5s %8s %8s %9s %9s %-16s", "strategy", "n", "rho", "IR", "필요IR", "ΔIR", "verdict_ci")
rows <- list()
for (j in KEEP) {
  S <- SER[[j]]
  X <- merge(inc[, .(m, date, ret_net, benchmark_ret)], S[, .(m, r)], by="m")
  if (nrow(X) < 60) next
  o <- bm_delta_ir(X[, .(date, ret_net = r)], weight = 0.20, incumbent = inc, B_boot = 600L)
  if (is.null(o$delta_ir)) next
  nd <- need_ir(o$correlation_with_incumbent)
  say("  %-30s %5d %+8.3f %+8.3f %9s %+9.4f %-16s", substr(NMS[j],1,30), o$n_overlap,
      o$correlation_with_incumbent, o$sleeve_standalone_ir,
      if (is.na(nd)) "불가" else sprintf("%.3f", nd), o$delta_ir, o$verdict_ci)
  ci <- o$delta_ir_ci
  rows[[length(rows)+1L]] <- data.table(id=NMS[j], n=o$n_overlap,
    rho=o$correlation_with_incumbent, ir=o$sleeve_standalone_ir, need=nd,
    short=if (is.na(nd)) NA_real_ else nd - o$sleeve_standalone_ir,
    dIR=o$delta_ir, lo=if (isTRUE(ci$available)) ci$lo else NA_real_,
    hi=if (isTRUE(ci$available)) ci$hi else NA_real_, verdict=o$verdict_ci)
}
R <- rbindlist(rows, fill=TRUE)
R[, self_like := rho > 0.95]
say("=== ★분포 ===")
say("  측정 %d · 자기유사(rho>0.95, PG2 파생 의심) %d → 제외 후 %d",
    nrow(R), sum(R$self_like), sum(!R$self_like))
V <- R[self_like == FALSE]
if (!nrow(V)) { say("  ★전건 자기유사 — 독립 재료 0"); quit(status=0) }
say("  rho     중앙 %+.3f · [%.3f, %.3f] · <0.4 인 계열 %d", median(V$rho), min(V$rho), max(V$rho), sum(V$rho<0.4))
say("  ★IR    중앙 %+.3f · [%.3f, %.3f] · **>=0.7 인 계열 %d**", median(V$ir), min(V$ir), max(V$ir), sum(V$ir>=0.7))
say("  부족분 중앙 %.3f · **최소 %.3f** (팩터DB 최소 0.142 대비 %s)",
    median(V$short, na.rm=TRUE), min(V$short, na.rm=TRUE),
    if (min(V$short, na.rm=TRUE) < 0.142) "★개선" else "미달")
say("  ΔIR    중앙 %+.4f · 최고 %+.4f (%s)", median(V$dIR), max(V$dIR), V[which.max(dIR), id])
say("=== ★판정 ===")
say("  1급(IR >= 필요): **%d / %d**", sum(V$ir >= V$need, na.rm=TRUE), nrow(V))
say("  CI 하단 >= 0.05 : **%d / %d**", sum(V$lo >= 0.05, na.rm=TRUE), nrow(V))
say("  점추정 >= 0.05  : %d / %d", sum(V$dIR >= 0.05, na.rm=TRUE), nrow(V))
if (any(V$ir >= 0.7, na.rm=TRUE)) {
  say("  ★★**IR 0.7+ 재료 발견 %d건**:", sum(V$ir >= 0.7, na.rm=TRUE))
  for (i in which(V$ir >= 0.7)) say("    %-30s IR %+.3f · rho %+.3f · 필요 %.3f · 부족 %+.3f · ΔIR %+.4f (%s)",
    substr(V$id[i],1,30), V$ir[i], V$rho[i], V$need[i], V$short[i], V$dIR[i], V$verdict[i])
} else say("  ★IR 0.7+ 재료 **0건** — 완성 전략 풀도 표적에 못 미친다")
say("=== 근접 5 ===")
for (i in order(V$short)[1:min(5,nrow(V))])
  say("  %-30s rho %+.3f · IR %+.3f · 부족 %.3f · ΔIR %+.4f · CI [%+.4f, %+.4f]",
      substr(V$id[i],1,30), V$rho[i], V$ir[i], V$short[i], V$dIR[i], V$lo[i], V$hi[i])
fwrite(R, file.path(OUT,"s2_strategies.csv"))
say("=== s2 완료 ===")
