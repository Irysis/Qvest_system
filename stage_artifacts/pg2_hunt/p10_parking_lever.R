## p10 — ★일반화 검정: 조건부 파킹이 **일반 레버**인가, 계약 고유인가
## p9 발견: 계약 국면규칙은 상관을 0.564→0.140 으로 낮춰 문턱을 1.135→0.576 으로 41% 내렸다.
## 가설 H: "OFF 월에 벤치를 보유하는 구조" 자체가 상관을 낮추므로 **어떤 재료에도** 적용 가능하다.
## 반가설 H0: 계약 신호의 국면 라벨이 계약 신호에 특수하게 맞아서 된 것이다.
## ⇒ 같은 라벨을 DB 48재료에 적용해 ΔIR 변화를 측정하고, **무작위 파킹 대조**와 비교한다.
##   ★무작위 파킹도 상관을 낮춘다(p3 에서 귀무 6.2% 통과 확인). 따라서 라벨 적용치가
##     무작위 파킹 분포를 넘지 못하면 "라벨은 무정보, 파킹 구조만 작동" 이 판정이다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p10] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
A <- readRDS(file.path(OUT,"factor_long.rds")); M <- readRDS(file.path(OUT,"mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
k_on <- sum(Mru$regime); n_mo <- nrow(Mru)
say("=== 국면 라벨 실측 === %d개월 · ON %d (%.1f%%) · 에피소드 %d",
    n_mo, k_on, 100*k_on/n_mo, sum(diff(c(0L, as.integer(Mru$regime)))==1L))

FN <- sort(unique(A$Factor_Name)); sel <- unique(FN[round(seq(1, length(FN), length.out = 48))])
say("=== 표본 %d재료 · 3-arm 비교 (무조건부 / 국면라벨 / 무작위파킹 30회 중앙) ===", length(sel))

applyR <- function(PR, rv, dates) {
  X <- merge(PR[, .(date, ret_net, benchmark_ret)], data.table(date=dates, regime=rv), by="date")
  if (!nrow(X)) return(NULL)
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  X[, r := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
  bm_delta_ir(X[, .(date, ret_net=r)], weight = 0.20, incumbent = inc)
}
set.seed(20260809)
RND <- lapply(1:30, function(i) { v <- rep(FALSE, n_mo); v[sample.int(n_mo, k_on)] <- TRUE; v })

rows <- list(); t0 <- Sys.time()
for (j in seq_along(sel)) {
  f <- sel[j]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) next
  PR <- as.data.table(r$period_returns)
  ## arm1: 무조건부 — 단 국면창(73개월)으로 잘라 **동일 창 비교** (창 차이를 효과로 오독 방지)
  PRw <- PR[date %in% Mru$date]
  a1 <- bm_delta_ir(PRw[, .(date, ret_net)], weight=0.20, incumbent=inc)
  a2 <- applyR(PR, Mru$regime, Mru$date)
  a3 <- vapply(RND, function(v) { o <- applyR(PR, v, Mru$date)
        if (is.null(o) || is.null(o$delta_ir)) NA_real_ else o$delta_ir }, numeric(1))
  if (is.null(a1$delta_ir) || is.null(a2$delta_ir)) next
  rows[[length(rows)+1L]] <- data.table(factor=f,
    d_uncond = a1$delta_ir, cor_uncond = a1$correlation_with_incumbent, ir_uncond = a1$sleeve_standalone_ir,
    d_regime = a2$delta_ir, cor_regime = a2$correlation_with_incumbent, ir_regime = a2$sleeve_standalone_ir,
    d_rand_med = median(a3, na.rm=TRUE), d_rand_p95 = quantile(a3,.95,na.rm=TRUE),
    beats_rand = a2$delta_ir > quantile(a3,.95,na.rm=TRUE))
  if (j %% 12 == 0) say("  ... %d/%d (%.1f분)", j, length(sel), as.numeric(difftime(Sys.time(),t0,units="mins")))
}
D <- rbindlist(rows)
say("=== 결과 %d재료 (전부 동일 73개월 창) ===", nrow(D))
say("  [A] 무조건부   ΔIR 중앙 %+.4f · 상관 중앙 %+.3f · IR 중앙 %+.3f",
    median(D$d_uncond), median(D$cor_uncond), median(D$ir_uncond))
say("  [B] 국면라벨   ΔIR 중앙 %+.4f · 상관 중앙 %+.3f · IR 중앙 %+.3f",
    median(D$d_regime), median(D$cor_regime), median(D$ir_regime))
say("  [C] 무작위파킹 ΔIR 중앙 %+.4f (재료별 30회 중앙의 중앙)", median(D$d_rand_med))
say("=== ★검정 1: 파킹 구조가 상관을 낮추는가 (B vs A) ===")
say("  상관 변화 중앙 %+.3f (A %+.3f → B %+.3f) · 낮아진 재료 %d/%d",
    median(D$cor_regime - D$cor_uncond), median(D$cor_uncond), median(D$cor_regime),
    sum(D$cor_regime < D$cor_uncond), nrow(D))
tt <- t.test(D$cor_regime, D$cor_uncond, paired = TRUE)
say("  paired t = %+.3f · p = %.5f → %s", tt$statistic, tt$p.value,
    if (tt$p.value < 0.05 && median(D$cor_regime - D$cor_uncond) < 0) "★파킹이 상관을 낮춘다(확인)" else "미확인")
say("=== ★검정 2: ΔIR 이 개선되는가 (B vs A) ===")
t2 <- t.test(D$d_regime, D$d_uncond, paired = TRUE)
say("  ΔIR 변화 중앙 %+.4f · 개선 재료 %d/%d · paired t %+.3f · p %.5f",
    median(D$d_regime - D$d_uncond), sum(D$d_regime > D$d_uncond), nrow(D), t2$statistic, t2$p.value)
say("  ★국면라벨 적용 후 ΔIR>=0.05 통과: **%d/%d**", sum(D$d_regime >= 0.05), nrow(D))
say("=== ★검정 3 (결정적): 라벨이 무작위 파킹보다 나은가 (B vs C) ===")
t3 <- t.test(D$d_regime, D$d_rand_med, paired = TRUE)
say("  B - C 중앙 %+.4f · paired t %+.3f · p %.5f", median(D$d_regime - D$d_rand_med), t3$statistic, t3$p.value)
say("  ★재료별로 라벨이 무작위 95 백분위를 넘은 비율 = **%d/%d (%.1f%%)**",
    sum(D$beats_rand, na.rm=TRUE), nrow(D), 100*mean(D$beats_rand, na.rm=TRUE))
say("  (귀무에서 기대 = 5%%. 크게 넘으면 라벨이 일반 정보를 담고 있다)")
say("=== ★판정 ===")
gen <- t3$p.value < 0.05 && median(D$d_regime - D$d_rand_med) > 0
say("  %s", if (gen) "★★국면 라벨은 **일반 레버**다 — DB 재료에도 무작위 파킹 이상으로 작동" else
  "★국면 라벨은 **계약 신호 고유**다 — DB 재료에 적용하면 무작위 파킹과 구분 안 됨")
say("  ⇒ %s", if (sum(D$d_regime >= 0.05) > 0)
  sprintf("파킹 적용 후 문턱 통과 %d건 — 후속 검증 대상", sum(D$d_regime >= 0.05)) else
  "파킹을 적용해도 DB 단일 재료는 0건 통과 — 재료 자체의 IR 부족이 지배")
fwrite(D, file.path(OUT,"p10_parking.csv"))
say("=== p10 완료 ===")
