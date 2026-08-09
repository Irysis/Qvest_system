## p1 — STR_1698 에 **다른 라벨**로 파킹 적용 (FQ-191 라벨 73개월 장벽 우회)
## 장벽의 정체: FQ-191 mega_spread 라벨이 2020-02~2026-02(73개월)뿐이라 STR_1698(~2024-04)과 겹침 51<60.
## ★그런데 `unified_regime_signal_daily` 의 Regime_Score 는 **269개월**(2004~2026)을 덮는다.
##   STR_1698 과 겹침이 ~240개월 → 파킹 적용 가능.
## ★라벨 정합: z3 이 확정 — `Category==RISK_ON` ⟺ `Regime_Score` **하위 71.7%** (일치 100.0% · phi 1.000)
## ★검증 의무: 새 라벨은 새 자유도다. 무작위 파킹 대조 + subsample_null 게이트 동반.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
source("02_Infrastructure/contracts/proxy_axis.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
j <- which(INV$names == "STR_1698_WT008_M08_Swap")[1]
S <- INV$ser[[j]]
say("=== 재료 === STR_1698 %d개월 · m [%d, %d]", nrow(S), min(S$m), max(S$m))

## 라벨 구성 (월말 → 익월 적용 · z3 확정 축·방향)
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1))
dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
mo <- U[!is.na(.dd)][order(.dd)][, .(cat = last(Category), rs = last(Regime_Score)), by = .(m = mi(.dd))]
mo[, m_apply := m + 1L]
## ★대리 축 재현 확인 (오늘 만든 계약)
pr <- proxy_reproduction(mo$cat == "RISK_ON", mo$rs, "low")
say("=== 라벨 축 재현 확인 (proxy_axis 계약) ===")
say("  Regime_Score(low) vs Category==RISK_ON: 일치 **%.1f%%** · phi %+.3f · 무작위 기대 %.1f%% · qualified %s",
    100*pr$agree, pr$phi, 100*pr$expected_agreement, pr$qualified)
if (!isTRUE(pr$qualified)) { say("  ★대리 축 부적격 — 중단"); quit(status=0) }

X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")
say("=== 겹침 === PG2 ∩ STR_1698 = %d개월", nrow(X))
say("=== ★발화율별 파킹 (라벨 창이 넓어 여러 문턱 가능) ===")
say("  %8s %6s %6s %8s %8s %9s %9s %-14s", "발화율","ON","n","rho","IR","필요IR","ΔIR","verdict_ci")
rows <- list()
for (p in c(0.717, 0.50, 0.35)) {
  th <- quantile(mo$rs, p, na.rm=TRUE)
  LB <- data.table(m = mo$m_apply, on = mo$rs <= th)[!is.na(on)]
  W <- merge(X, LB, by="m")[order(m)]
  if (nrow(W) < 60) { say("  %7.1f%% (겹침 %d<60)", 100*p, nrow(W)); next }
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, B_boot=800L)
  if (is.null(o$delta_ir)) { say("  %7.1f%% %s", 100*p, o$status); next }
  nd <- need_ir(o$correlation_with_incumbent); ci <- o$delta_ir_ci
  say("  %7.1f%% %6d %6d %+8.3f %+8.3f %9.3f %+9.4f %-14s", 100*p, sum(W$on), nrow(W),
      o$correlation_with_incumbent, o$sleeve_standalone_ir, nd, o$delta_ir, o$verdict_ci)
  rows[[length(rows)+1L]] <- data.table(rate=p, n_on=sum(W$on), n=nrow(W),
    rho=o$correlation_with_incumbent, ir=o$sleeve_standalone_ir, need=nd,
    short=nd-o$sleeve_standalone_ir, dIR=o$delta_ir,
    lo=if (isTRUE(ci$available)) ci$lo else NA_real_,
    hi=if (isTRUE(ci$available)) ci$hi else NA_real_, verdict=o$verdict_ci, W=list(W))
}
if (!length(rows)) { say("=== ★전 발화율 실패 — 정지 ==="); quit(status=0) }
R <- rbindlist(lapply(rows, function(x) x[, !"W"]), fill=TRUE)
say("=== ★무처리 대조 (같은 창) ===")
o0 <- bm_delta_ir(X[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
n0 <- need_ir(o0$correlation_with_incumbent)
say("  rho %+.3f · IR %+.3f · 필요 %.3f · **부족 %+.3f** · ΔIR %+.4f",
    o0$correlation_with_incumbent, o0$sleeve_standalone_ir, n0,
    n0-o0$sleeve_standalone_ir, o0$delta_ir)
say("=== ★판정 ===")
say("  파킹 후 최소 부족분 **%+.3f** (발화율 %.1f%%) vs 무처리 %+.3f",
    min(R$short), 100*R[which.min(short), rate], n0-o0$sleeve_standalone_ir)
say("  1급(IR>=필요) **%d/%d** · CI 하단>=0.05 **%d/%d**",
    sum(R$short <= 0, na.rm=TRUE), nrow(R), sum(R$lo >= 0.05, na.rm=TRUE), nrow(R))
say("  최고 ΔIR %+.4f · CI [%+.4f, %+.4f]", max(R$dIR), R[which.max(dIR), lo], R[which.max(dIR), hi])
## 귀무 창 게이트
best <- rows[[which.max(R$dIR)]]; W <- best$W[[1]]
g <- subsample_null(W$r - W$benchmark_ret,
                    merge(W[, .(m)], inc[, .(m, active)], by="m")$active, W$on, n_draw = 1000L)
if (isTRUE(g$available))
  say("  귀무 창 게이트: Δrho %+.4f · [%+.4f, %+.4f] · 백분위 **%.1f%%** · inside %s",
      g$delta, g$null_q05, g$null_q95, g$percentile, g$inside)
fwrite(R, file.path(OUT,"p1_str1698_altlabel.csv"))
say("=== p1 완료 ===")
