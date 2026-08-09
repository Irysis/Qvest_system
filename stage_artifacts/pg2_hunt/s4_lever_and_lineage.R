## s4 — ①근접 전략에 파킹 레버 적용(창 정합) ②rho 0.7+ 6계열의 계보 확인
## 최고 실질 후보: STR_1698_WT008_M08_Swap — rho 0.192 · IR 0.560 · 필요 0.647 · **부족 0.087**
##   (팩터DB 최고 V18_AM 부족 0.142 대비 개선)
## 파킹 실측 효과(창 정합): rho −0.236 · IR +0.379 → 필요 IR 이 내려가고 IR 이 오른다.
## ★창 정합 필수 — 파킹은 73개월 창이므로 baseline 도 같은 창에서 재비교한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s4] ", fmt, "\n"), ...)); flush.console() }
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

TARGET <- c("STR_1698_WT008_M08_Swap","WT_D20260424_009_pilot11","WT_WT-D20260610_001",
            "STR_1661_XGB_GPU.1","STR_1675_QRebal_Hybrid","STR_1696_WT007_RegimeSigma_MinCVaR")
say("=== ① 파킹 레버 (창 정합 3-arm) ===")
say("  %-34s %6s %8s %8s %8s | %8s %8s %8s %9s", "strategy","n","A rho","A IR","A 부족","P rho","P IR","P 부족","ΔIR(P)")
rows <- list()
for (nm in TARGET) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")
  W <- merge(X, LB, by="m")                       # 파킹 창 73개월
  if (nrow(W) < 40) { say("  %-34s (파킹 창 겹침 %d 부족)", substr(nm,1,34), nrow(W)); next }
  ## A: 같은 73개월 창의 무처리
  a <- bm_delta_ir(W[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  ## P: 파킹 (ON=전략, OFF=벤치, 전환 15bps)
  W2 <- copy(W)[order(m)][, sw := c(0L, abs(diff(as.integer(on))))]
  W2[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  p <- bm_delta_ir(W2[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, B_boot=600L)
  if (is.null(a$delta_ir) || is.null(p$delta_ir)) next
  na_ <- need_ir(a$correlation_with_incumbent); np <- need_ir(p$correlation_with_incumbent)
  say("  %-34s %6d %+8.3f %+8.3f %+8.3f | %+8.3f %+8.3f %+8.3f %+9.4f", substr(nm,1,34), nrow(W),
      a$correlation_with_incumbent, a$sleeve_standalone_ir, na_-a$sleeve_standalone_ir,
      p$correlation_with_incumbent, p$sleeve_standalone_ir, np-p$sleeve_standalone_ir, p$delta_ir)
  ci <- p$delta_ir_ci
  rows[[length(rows)+1L]] <- data.table(id=nm, n=nrow(W),
    A_rho=a$correlation_with_incumbent, A_ir=a$sleeve_standalone_ir, A_short=na_-a$sleeve_standalone_ir,
    P_rho=p$correlation_with_incumbent, P_ir=p$sleeve_standalone_ir, P_short=np-p$sleeve_standalone_ir,
    P_d=p$delta_ir, P_lo=if (isTRUE(ci$available)) ci$lo else NA_real_, verdict=p$verdict_ci)
}
R <- rbindlist(rows, fill=TRUE)
if (nrow(R)) {
  say("=== ★파킹 효과 ===")
  say("  rho 변화 중앙 %+.4f · IR 변화 중앙 %+.4f · 부족분 변화 중앙 %+.4f",
      median(R$P_rho-R$A_rho), median(R$P_ir-R$A_ir), median(R$P_short-R$A_short))
  say("  ★파킹 후 통과(P_ir >= 필요): **%d / %d** · CI 하단>=0.05: **%d**",
      sum(R$P_short <= 0, na.rm=TRUE), nrow(R), sum(R$P_lo >= 0.05, na.rm=TRUE))
  say("  최소 부족분: A %+.3f (%s) → P **%+.3f** (%s)",
      min(R$A_short), R[which.min(A_short), id], min(R$P_short), R[which.min(P_short), id])
  fwrite(R, file.path(OUT,"s4_parked.csv"))
}

say("=== ② rho 0.7+ 6계열의 계보 확인 (파일 경로로) ===")
IDX <- INV$idx
HI <- c("WT-D20260508_009","WT-D20260508_010.2","WT-D20260508_013.1","WT-D20260508_013.3",
        "WT_WT-S20260504_002","WT_WT-S20260504_004")
for (nm in HI) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  f <- IDX$file[j]
  say("  %-24s → %s", substr(nm,1,24), substr(gsub(paste0("^", ROOT, "/?"), "", gsub("\\\\","/",f)), 1, 92))
}
say("  ★경로에 STR_1715/1716 계열 또는 PG2 산출물이 보이면 자기 파생이다")
say("=== s4 완료 ===")
