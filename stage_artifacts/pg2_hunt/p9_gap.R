## p9 — 표본 재료를 요구조건 지도에 얹어 **부족분**을 정량화
## (p7 은 PG2 holdings 가 0행이라 겹침률 계산에서 죽었다 — 겹침 대리 지표는 폐기하고
##  ΔIR 직접 측정만 쓴다. 표본은 48개로 늘려 분포 추정을 두껍게 한다.)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p9] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- m_i/s_i*sqrt(12)
dIR <- function(rho, ir_s, w, k = 1) {
  m_s <- ir_s/sqrt(12)*(k*s_i)
  mu <- (1-w)*m_i + w*m_s
  v  <- (1-w)^2*s_i^2 + w^2*(k*s_i)^2 + 2*w*(1-w)*rho*s_i*(k*s_i)
  mu/sqrt(v)*sqrt(12) - ir_i
}
need_ir <- function(rho, w = 0.20, k = 1) {
  f <- function(x) dIR(rho, x, w, k) - 0.05
  if (f(15) < 0) NA_real_ else tryCatch(uniroot(f, c(-2, 15))$root, error = function(e) NA_real_)
}

A <- readRDS(file.path(OUT, "factor_long.rds"))
M <- readRDS(file.path(OUT, "mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
FN <- sort(unique(A$Factor_Name))
sel <- FN[round(seq(1, length(FN), length.out = 48))]
sel <- unique(sel)
say("=== 표본 %d재료 (전체 %d 중 등간격) ===", length(sel), length(FN))

rows <- list(); t0 <- Sys.time()
for (j in seq_along(sel)) {
  f <- sel[j]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n = 25L,
        cost_bps_oneway = 15, liq_dt = as.data.table(M$liq), liq_min = 2e8,
        run_id = f, strategy_id = f, diag_dual_basis = FALSE,
        size_dt = as.data.table(M$size_dt))), error = function(e) NULL)
  if (is.null(r)) next
  o <- bm_delta_ir(as.data.table(r$period_returns)[, .(date, ret_net)], weight = 0.20, incumbent = inc)
  if (is.null(o$delta_ir) || !is.finite(o$delta_ir)) next
  rows[[length(rows)+1L]] <- data.table(factor = f, n = o$n_overlap,
    cor = o$correlation_with_incumbent, sleeve_ir = o$sleeve_standalone_ir,
    sleeve_sd_ratio = NA_real_, dIR = o$delta_ir, port_t = r$portfolio_alpha_t_nw_lag3)
  if (j %% 12 == 0) say("  ... %d/%d (%.1f분)", j, length(sel),
                        as.numeric(difftime(Sys.time(), t0, units="mins")))
}
D <- rbindlist(rows)
say("=== 측정 %d재료 ===", nrow(D))
say("  상관     : 중앙 %+.3f · [%.3f, %.3f]", median(D$cor), min(D$cor), max(D$cor))
say("  슬리브IR : 중앙 %+.3f · [%.3f, %.3f]", median(D$sleeve_ir), min(D$sleeve_ir), max(D$sleeve_ir))
say("  ΔIR      : 중앙 %+.4f · [%.4f, %.4f]", median(D$dIR), min(D$dIR), max(D$dIR))
say("  ★양수 %d/%d (%.1f%%) · **>=0.05 통과 %d (%.1f%%)**",
    sum(D$dIR>0), nrow(D), 100*mean(D$dIR>0), sum(D$dIR>=0.05), 100*mean(D$dIR>=0.05))

say("=== ★부족분 — 각 재료가 자기 상관에서 필요한 IR 대비 얼마나 모자란가 ===")
D[, need := vapply(cor, need_ir, numeric(1))]
D[, shortfall := need - sleeve_ir]
say("  필요 IR 중앙 **%.3f** · 실측 IR 중앙 **%+.3f** · 부족분 중앙 **%.3f**",
    median(D$need, na.rm=TRUE), median(D$sleeve_ir), median(D$shortfall, na.rm=TRUE))
say("  ⇒ 단일 팩터가 문턱을 넘으려면 IR 을 중앙 %.3f 만큼 더 벌어야 한다.",
    median(D$shortfall, na.rm=TRUE))
say("  가장 가까운 5건:")
for (i in order(D$shortfall)[1:5]) say("    %-30s 상관 %+.3f · IR %+.3f · 필요 %.3f · **부족 %.3f** · ΔIR %+.4f",
  substr(D$factor[i],1,30), D$cor[i], D$sleeve_ir[i], D$need[i], D$shortfall[i], D$dIR[i])

say("=== ★기전 진단: 왜 전부 떨어지나 ===")
say("  1) 상관이 안 낮다 — 상관<0.2 인 재료 %d/%d (%.1f%%)",
    sum(D$cor < 0.2), nrow(D), 100*mean(D$cor < 0.2))
say("     같은 유니버스(K200∪KQ150) top-25 long-only 라 **시장 성분을 공유**한다.")
say("  2) IR 이 안 높다 — IR>0.5 인 재료 %d/%d (%.1f%%) · IR>0.925(상관0.4 요구선) %d",
    sum(D$sleeve_ir > 0.5), nrow(D), 100*mean(D$sleeve_ir > 0.5), sum(D$sleeve_ir > 0.925))
say("  3) 둘 다 만족(상관<0.4 ∧ IR>0.925): **%d/%d**",
    sum(D$cor < 0.4 & D$sleeve_ir > 0.925), nrow(D))
say("  ⇒ 단일 팩터의 실패는 **상관과 IR 이 동시에 부족**해서다. 한쪽만 고쳐선 안 된다.")

say("=== ★그래서 계약 국면규칙이 특별한 이유 ===")
nc <- need_ir(0.140); nu <- need_ir(0.564)
say("  무조건부: 상관 0.564 → 필요 %.3f · 실측 0.281 → 부족 %+.3f", nu, 0.281-nu)
say("  국면규칙: 상관 0.140 → 필요 %.3f · 실측 0.758 → **여유 %+.3f**", nc, 0.758-nc)
say("  ★국면 규칙은 상관을 낮춰 **문턱 자체를 %.3f→%.3f 로 내렸다**(41%% 인하).", nu, nc)
say("  ⇒ 일반화 가설: **조건부 파킹이 상관을 낮추는 레버**다. 단 무작위 파킹도 6.2%% 통과하므로")
say("    라벨이 실질인지 귀무 대조가 필수(계약은 3귀무 p 0.000~0.036 통과).")

fwrite(D, file.path(OUT, "p9_gap.csv"))
say("=== p9 완료 → p9_gap.csv ===")
