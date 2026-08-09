## c7 — ★근접 재료 합성: 남은 갭(IR)을 분산 효과로 메울 수 있는가
## 전수 결과: 통과 0/331 · 부족분 중앙 0.834 · 최소 0.142(V18_AM).
## 남은 갭은 **IR** 이다(상관은 파킹으로 0.32까지 내려감). 합성은 IR 을 올리는 직접 레버다.
## ★선행: 근접 12건에 **중복 팩터** 의심(수치 완전 동일 쌍 3개). 중복을 섞으면 분산 효과가 0 이다.
##   → 실제 z 벡터로 중복을 먼저 검거하고 **고유 재료만** 합성한다.
## ★대조 의무: 무작위 합성(같은 K) 200회. 선별이 무작위를 못 넘으면 선별은 무정보.
## ★판정은 계약의 verdict_ci 로 한다(점추정 금지 — 오늘 확립).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c7] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

A  <- readRDS(file.path(OUT,"factor_long.rds"))
M  <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
TB <- fread(file.path(OUT,"c6_full_table.csv"))
inc <- bm_load_incumbent()

say("=== 1. ★중복 팩터 검거 (근접 30건의 z 벡터 실측 비교) ===")
cand <- TB[is.finite(short_best)][order(short_best)][1:30, factor]
W <- dcast(A[Factor_Name %in% cand], Date + Ticker ~ Factor_Name, value.var = "z")
mat <- as.matrix(W[, ..cand]); colnames(mat) <- cand
CM <- suppressWarnings(cor(mat, use = "pairwise.complete.obs"))
dups <- which(abs(CM) > 0.999 & upper.tri(CM), arr.ind = TRUE)
say("  후보 %d개 · 상호상관 |r|>0.999 쌍: **%d건**", length(cand), nrow(dups))
if (nrow(dups)) for (i in seq_len(nrow(dups)))
  say("    %-30s ≡ %-30s r=%+.6f", rownames(CM)[dups[i,1]], colnames(CM)[dups[i,2]], CM[dups[i,1],dups[i,2]])
## greedy 로 고유 집합 추출 (부족분 순서 유지)
keep <- character(0)
for (f in cand) {
  if (!length(keep)) { keep <- f; next }
  if (max(abs(CM[f, keep]), na.rm = TRUE) < 0.95) keep <- c(keep, f)
}
say("  ⇒ 고유 재료 **%d/%d** (|r|<0.95 기준): %s", length(keep), length(cand),
    paste(substr(keep,1,18), collapse=", "))
say("  고유 집합 내 최대 상호상관 %.3f", max(abs(CM[keep,keep][upper.tri(CM[keep,keep])]), na.rm=TRUE))

measure <- function(fs, label, parked) {
  S <- A[Factor_Name %in% fs, .(z = mean(z, na.rm=TRUE)), by = .(Date, Ticker)]
  setnames(S, "z", "score")
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=label,
        strategy_id=label, diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))),
        error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)
  if (parked) {
    Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
    if (!nrow(X)) return(NULL)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    PR <- X[, .(date, ret_net = r2)]
  } else PR <- PR[, .(date, ret_net)]
  bm_delta_ir(PR, weight = 0.20, incumbent = inc, B_boot = 600L)
}

say("=== 2. 선별 합성 (부족분 상위 고유 K개, 단순 평균 z) ===")
say("  %-8s %-9s %8s %8s %9s %10s %10s %-14s", "K", "arm", "상관", "IR", "ΔIR", "CI하단", "CI상단", "verdict_ci")
res <- list()
for (K in c(2,3,5,8)) for (pk in c(FALSE, TRUE)) {
  fs <- head(keep, K)
  o <- measure(fs, sprintf("SEL_K%d_%s", K, if (pk) "PK" else "UN"), pk)
  if (is.null(o) || is.null(o$delta_ir)) { say("  %-8d %-9s (측정 실패)", K, if (pk) "parked" else "uncond"); next }
  ci <- o$delta_ir_ci
  say("  %-8d %-9s %+8.3f %+8.3f %+9.4f %+10.4f %+10.4f %-14s", K, if (pk) "parked" else "uncond",
      o$correlation_with_incumbent, o$sleeve_standalone_ir, o$delta_ir,
      ci$lo %||% NA_real_, ci$hi %||% NA_real_, o$verdict_ci)
  res[[length(res)+1L]] <- data.table(sel="selected", K=K, arm=if (pk) "parked" else "uncond",
    cor=o$correlation_with_incumbent, ir=o$sleeve_standalone_ir, dIR=o$delta_ir,
    lo=ci$lo %||% NA_real_, hi=ci$hi %||% NA_real_, verdict=o$verdict_ci, n=o$n_overlap)
}
`%||%` <- function(a,b) if (is.null(a)) b else a

say("=== 3. ★대조: 무작위 합성 (같은 K · 60회) — 선별이 무정보인지 검정 ===")
FN <- sort(unique(A$Factor_Name))
set.seed(20260809)
for (K in c(3,8)) for (pk in c(FALSE, TRUE)) {
  ds <- vapply(seq_len(60L), function(i) {
    o <- measure(sample(FN, K), sprintf("RND%d", i), pk)
    if (is.null(o) || is.null(o$delta_ir)) NA_real_ else o$delta_ir }, numeric(1))
  ds <- ds[is.finite(ds)]
  sel <- res[K == get("K") & arm == (if (pk) "parked" else "uncond"), dIR]
  say("  K=%d %-7s 무작위 ΔIR 중앙 %+.4f · [5%%,95%%] [%+.4f, %+.4f] · >=0.05 %.1f%%",
      K, if (pk) "parked" else "uncond", median(ds), quantile(ds,.05), quantile(ds,.95), 100*mean(ds>=0.05))
  if (length(sel)) say("       ★선별 %+.4f 의 무작위 대비 백분위 = **%.1f%%**", sel[1], 100*mean(ds < sel[1]))
}

say("=== 4. ★판정 ===")
R <- rbindlist(res, fill=TRUE)
say("  선별 합성 %d셀 중 verdict_ci=BEATS_PG2 **%d** · UNRESOLVED %d · 미달 %d",
    nrow(R), sum(R$verdict=="BEATS_PG2"), sum(R$verdict=="UNRESOLVED"),
    sum(!R$verdict %in% c("BEATS_PG2","UNRESOLVED")))
say("  최고 ΔIR %+.4f (K=%d %s) · CI [%+.4f, %+.4f]",
    max(R$dIR), R[which.max(dIR), K], R[which.max(dIR), arm],
    R[which.max(dIR), lo], R[which.max(dIR), hi])
say("  단일 최고(V18_AM parked) ΔIR +0.0201 대비 %s",
    if (max(R$dIR) > 0.0201) sprintf("★합성이 개선 (+%.4f)", max(R$dIR)-0.0201) else "합성 이득 없음")
say("  ★합성이 IR 을 올렸는가: 단일 최고 IR 0.576 vs 합성 최고 IR %+.3f", max(R$ir))
fwrite(R, file.path(OUT,"c7_composite.csv"))
say("=== c7 완료 ===")
