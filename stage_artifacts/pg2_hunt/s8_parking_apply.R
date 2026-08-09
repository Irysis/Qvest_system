## s8 — 파킹 가능한 후보에 레버 적용 (창 정합 · 실패는 사유별 집계 · 조용한 skip 금지)
## s7: 파킹 가능 39/40 · 비계보 37. 최선 = WT_D20260424_009_pilot11 (rho 0.132 · IR 0.431 · 부족 0.135)
## 파킹 실측 효과(창 정합 30재료): rho −0.236 · IR +0.379 → 필요 IR 하락 + IR 상승 양쪽.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s8] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
C <- fread(file.path(OUT,"s7_census.csv"))
TG <- C[park_ok == TRUE & lineage == FALSE][order(short)][1:12, id]
say("=== 대상 %d계열 (파킹 가능 ∧ 비계보, 부족분 상위) ===", length(TG))
say("  %-32s %6s %8s %8s %8s | %8s %8s %8s %9s %-14s",
    "strategy","n","A rho","A IR","A 부족","P rho","P IR","P 부족","ΔIR(P)","verdict_ci")
fails <- c(); rows <- list()
for (nm in TG) {
  j <- which(INV$names == nm)[1]
  if (is.na(j)) { fails <- c(fails, sprintf("%s: 이름 미발견", nm)); next }
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")
  W <- merge(X, LB, by="m")[order(m)]
  if (nrow(W) < 60) { fails <- c(fails, sprintf("%s: 파킹 겹침 %d<60", nm, nrow(W))); next }
  a <- bm_delta_ir(W[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  p <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, B_boot=600L)
  if (is.null(a$delta_ir) || !is.finite(a$delta_ir)) { fails <- c(fails, sprintf("%s: A %s", nm, a$status)); next }
  if (is.null(p$delta_ir) || !is.finite(p$delta_ir)) { fails <- c(fails, sprintf("%s: P %s", nm, p$status)); next }
  na_ <- need_ir(a$correlation_with_incumbent); np <- need_ir(p$correlation_with_incumbent)
  ci <- p$delta_ir_ci
  say("  %-32s %6d %+8.3f %+8.3f %+8.3f | %+8.3f %+8.3f %+8.3f %+9.4f %-14s", substr(nm,1,32), nrow(W),
      a$correlation_with_incumbent, a$sleeve_standalone_ir, na_-a$sleeve_standalone_ir,
      p$correlation_with_incumbent, p$sleeve_standalone_ir, np-p$sleeve_standalone_ir,
      p$delta_ir, p$verdict_ci)
  rows[[length(rows)+1L]] <- data.table(id=nm, n=nrow(W),
    A_rho=a$correlation_with_incumbent, A_ir=a$sleeve_standalone_ir, A_short=na_-a$sleeve_standalone_ir,
    P_rho=p$correlation_with_incumbent, P_ir=p$sleeve_standalone_ir, P_short=np-p$sleeve_standalone_ir,
    P_d=p$delta_ir, P_lo=if (isTRUE(ci$available)) ci$lo else NA_real_,
    P_hi=if (isTRUE(ci$available)) ci$hi else NA_real_, verdict=p$verdict_ci)
}
say("=== ★실패 집계 (조용한 skip 금지) === %d건", length(fails))
if (length(fails)) for (f in fails) say("    %s", f)
R <- rbindlist(rows, fill=TRUE)
if (!nrow(R)) { say("=== ★측정 0건 — 정지 ==="); quit(status=0) }
say("=== ★파킹 효과 (창 정합, n=%d) ===", nrow(R))
say("  rho  %+.3f → %+.3f (변화 중앙 %+.4f · 인하 %d/%d)",
    median(R$A_rho), median(R$P_rho), median(R$P_rho-R$A_rho), sum(R$P_rho<R$A_rho), nrow(R))
say("  IR   %+.3f → %+.3f (변화 중앙 %+.4f · 상승 %d/%d)",
    median(R$A_ir), median(R$P_ir), median(R$P_ir-R$A_ir), sum(R$P_ir>R$A_ir), nrow(R))
say("  부족 %+.3f → %+.3f (변화 중앙 %+.4f · 개선 %d/%d)",
    median(R$A_short), median(R$P_short), median(R$P_short-R$A_short), sum(R$P_short<R$A_short), nrow(R))
say("=== ★판정 ===")
say("  1급(P_ir >= 필요): **%d / %d**", sum(R$P_short <= 0, na.rm=TRUE), nrow(R))
say("  CI 하단 >= 0.05  : **%d / %d**", sum(R$P_lo >= 0.05, na.rm=TRUE), nrow(R))
say("  최소 부족분: A %+.3f (%s) → P **%+.3f** (%s)",
    min(R$A_short), R[which.min(A_short), id], min(R$P_short), R[which.min(P_short), id])
say("  최고 ΔIR %+.4f (%s) · CI [%+.4f, %+.4f]",
    max(R$P_d), R[which.max(P_d), id], R[which.max(P_d), P_lo], R[which.max(P_d), P_hi])
say("  ⇒ %s", if (any(R$P_short <= 0, na.rm=TRUE)) "★★통과 재료 발생 — 적대 검증 대상" else
  sprintf("★파킹 후에도 통과 0 — 최소 부족분 %.3f (오늘 팩터DB 최소 0.142 · 전략풀 무처리 최소 0.087 대비)",
          min(R$P_short, na.rm=TRUE)))
fwrite(R, file.path(OUT,"s8_parked.csv"))
say("=== s8 완료 ===")
