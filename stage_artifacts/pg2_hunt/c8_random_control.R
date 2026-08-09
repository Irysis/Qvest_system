## c8 — 합성 라운드의 무작위 대조 (c7 섹션3 이 data.table 스코프 버그로 죽어 분리)
## 버그: res[K == get("K")] 에서 K 가 **컬럼명이자 루프변수** → 자기 자신과 비교돼 무의미/에러.
##   교훈: data.table 안에서 루프 변수와 컬럼명을 같은 이름으로 쓰지 말 것.
## 선별 합성 실측(c7 섹션2, 이미 확보):
##   K=2 un -0.1268 / pk -0.0122 · K=3 un -0.1269 / pk -0.0079
##   K=5 un -0.1034 / pk -0.0040 · K=8 un -0.0504 / pk **+0.0071**
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c8] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
inc <- bm_load_incumbent()
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]

## 선별 실측치 (c7 섹션2 stdout — 하드코딩이 아니라 대조 기준점으로만 사용)
SEL <- data.table(kk = c(2,3,5,8,2,3,5,8),
                  parked = c(FALSE,FALSE,FALSE,FALSE,TRUE,TRUE,TRUE,TRUE),
                  dIR = c(-0.1268,-0.1269,-0.1034,-0.0504,-0.0122,-0.0079,-0.0040,+0.0071))

dIR_of <- function(fs, parked, boot = FALSE) {
  S <- A[Factor_Name %in% fs, .(score = mean(z, na.rm=TRUE)), by = .(Date, Ticker)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="R", strategy_id="R",
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NA_real_)
  PR <- as.data.table(r$period_returns)
  if (parked) {
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
    if (!nrow(X)) return(NA_real_)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    PR <- X[, .(date, ret_net = r2)]
  } else PR <- PR[, .(date, ret_net)]
  o <- bm_delta_ir(PR, weight = 0.20, incumbent = inc, bootstrap = boot)
  if (is.null(o$delta_ir)) NA_real_ else o$delta_ir
}

FN <- sort(unique(A$Factor_Name))
say("=== 무작위 합성 대조 (팩터 풀 %d · 각 40회) ===", length(FN))
say("  %-4s %-8s %10s %10s %10s %9s %12s", "K", "arm", "무작위중앙", "5%", "95%", ">=0.05", "선별 백분위")
set.seed(20260809)
rows <- list()
for (kk in c(3L, 8L)) for (pk in c(FALSE, TRUE)) {
  ds <- vapply(seq_len(40L), function(i) dIR_of(sample(FN, kk), pk), numeric(1))
  ds <- ds[is.finite(ds)]
  sel <- SEL[SEL$kk == kk & SEL$parked == pk, dIR][1]
  pct <- 100*mean(ds < sel)
  say("  %-4d %-8s %+10.4f %+10.4f %+10.4f %8.1f%% %11.1f%%",
      kk, if (pk) "parked" else "uncond", median(ds), quantile(ds,.05), quantile(ds,.95),
      100*mean(ds >= 0.05), pct)
  rows[[length(rows)+1L]] <- data.table(K=kk, arm=if (pk) "parked" else "uncond",
    rnd_med=median(ds), rnd_p05=quantile(ds,.05), rnd_p95=quantile(ds,.95),
    rnd_pass=mean(ds>=0.05), sel_dIR=sel, sel_pct=pct, n_draw=length(ds))
}
R <- rbindlist(rows)

say("=== ★판정 ===")
say("  1) 선별이 무작위를 넘는가 — 백분위 %s",
    paste(sprintf("%s K%d %.0f%%", R$arm, R$K, R$sel_pct), collapse=" · "))
say("     ⇒ %s", if (all(R$sel_pct > 95)) "★선별이 무작위 대비 유의" else
   sprintf("★선별이 무작위 95 백분위를 넘은 셀 **%d/%d** — 선별 규칙은 대체로 무정보",
           sum(R$sel_pct > 95), nrow(R)))
say("  2) 무작위 합성만으로 문턱을 넘는 비율: %s",
    paste(sprintf("%s K%d %.1f%%", R$arm, R$K, 100*R$rnd_pass), collapse=" · "))
say("  3) ★합성이 단일 최고를 넘는가")
say("     단일 최고 = V18_AM parked ΔIR **+0.0201** (부족분 0.142)")
say("     합성 최고 = K=8 parked ΔIR **+0.0071**")
say("     ⇒ ★합성이 단일 최고를 **못 넘는다**. 약한 재료를 섞으면 평균이 희석된다.")
say("  4) ★그래도 확인된 것: 합성은 **IR 을 K 와 함께 단조 증가**시킨다")
say("     parked IR: K2 0.413 → K3 0.422 → K5 0.433 → K8 **0.521** (분산 효과 실재)")
say("     동시에 상관도 낮춤: uncond K2 0.308 → K8 0.242")
say("     ⇒ 기전은 작동하나 **출발점(재료 IR)이 낮아** 문턱에 못 미친다 — 재료 병목 재확인")
say("  5) verdict_ci: 선별 8셀 전건 BEATS_PG2 **0건** (UNRESOLVED 6 · BELOW_THRESHOLD 2)")
fwrite(R, file.path(OUT,"c8_random_control.csv"))
say("=== c8 완료 ===")
