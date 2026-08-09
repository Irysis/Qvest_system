#!/usr/bin/env Rscript
# =============================================================================
# p0f_dupcheck.R — p0e [2] 의 상위 잔차-알파에 동일 수치가 반복됐다
#   (+0.482/t3.38 2건 · +0.558/t3.08 3건). 중복 모듈이면 "27건 유의"가 부풀려진 것.
#   ★유효 독립 개수를 확정하기 전에는 어떤 카운트도 인용하지 않는다.
# 겸사: 모듈-레벨 NAV 합성의 종목수(Production Constraint max 25) 실사.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0f.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M <- as.matrix(sub[, ..scrap_ok])
cov_m <- colSums(is.finite(M)); keep <- which(cov_m >= 253)
M <- M[complete.cases(M[, keep, drop = FALSE]), keep, drop = FALSE]
ids <- scrap_ok[keep]
cat(sprintf("=== INPUT: %d months x %d modules ===\n", nrow(M), ncol(M)))

cat("\n=== [1] EXACT / NEAR DUPLICATE DETECTION ===\n")
# 정확 중복 (바이트 동일 수익 벡터)
dig <- apply(M, 2, function(x) paste0(sprintf("%.10f", x), collapse = "|"))
tb <- table(dig)
n_exact_groups <- sum(tb > 1); n_exact_dupes <- sum(tb[tb > 1]) - n_exact_groups
cat(sprintf("  정확 중복 그룹=%d  중복으로 제거될 모듈=%d  → 고유 수익벡터=%d / %d\n",
            n_exact_groups, n_exact_dupes, length(tb), ncol(M)))
if (n_exact_groups > 0) {
  cat("  큰 중복 그룹 상위 5:\n")
  big <- sort(tb[tb > 1], decreasing = TRUE)[1:min(5, n_exact_groups)]
  for (i in seq_along(big)) {
    mem <- ids[dig == names(big)[i]]
    cat(sprintf("    그룹 %d (n=%d): %s\n", i, big[i], paste(head(mem, 4), collapse = ", ")))
  }
}
# 근사 중복 (corr >= 0.999)
C <- cor(M)
diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE)
hi <- hi[hi[, 1] < hi[, 2], , drop = FALSE]
cat(sprintf("  근사 중복 쌍 (corr>=0.999): %d 쌍\n", nrow(hi)))
for (thr in c(0.99, 0.995, 0.999, 0.9999)) {
  h <- which(C >= thr, arr.ind = TRUE); h <- h[h[,1] < h[,2], , drop = FALSE]
  cat(sprintf("    corr>=%.4f : %d 쌍\n", thr, nrow(h)))
}
# 연결성분으로 유효 독립 개수 산정 (corr>=0.999 를 동일로 간주)
# ★ 최상위 for 루프에서 `<<-` 는 globalenv 가 아니라 그 *상위* 환경을 찾는다 → object not found.
#   함수로 감싸 지역 상태로 처리한다 (2026-08-09 실측 오류 수정).
comp <- local({
  par <- seq_len(ncol(M))
  fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) {
    a <- fnd(hi[r, 1]); b <- fnd(hi[r, 2]); if (a != b) par[b] <- a
  }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
n_eff <- length(unique(comp))
cat(sprintf("  ★유효 독립 모듈 수 (corr>=0.999 병합) = %d / %d  (축소율 %.1f%%)\n",
            n_eff, ncol(M), 100 * (1 - n_eff / ncol(M))))

cat("\n=== [2] 중복 제거 후 잔차-알파 재계산 ===\n")
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
Mu <- M[, reps, drop = FALSE]; idu <- ids[reps]
bmw <- sub$bm[complete.cases(as.matrix(sub[, ..scrap_ok])[, keep, drop = FALSE])]
A <- Mu - matrix(bmw, nrow(Mu), ncol(Mu))
pc <- prcomp(scale(A), center = FALSE); f1 <- as.numeric(pc$x[, 1]); f1 <- f1 / sd(f1)
ev <- pc$sdev^2
cat(sprintf("  중복제거 후 PC1 share=%.3f  eff-N=%.2f  (n_mod=%d)\n",
            ev[1]/sum(ev), sum(ev)^2/sum(ev^2), ncol(A)))
fit <- t(apply(A, 2, function(y) { m <- summary(lm(y ~ f1))$coefficients; c(m[1,1], m[1,3]) }))
colnames(fit) <- c("alpha", "t")
cat(sprintf("  n(t>+2)=%d  n(t<-2)=%d  of %d   기대 오탐@5%%=%.1f\n",
            sum(fit[,"t"] > 2), sum(fit[,"t"] < -2), nrow(fit), 0.025*nrow(fit)))
set.seed(20260809)
nullc <- replicate(50, { yp <- A[sample(nrow(A)), , drop = FALSE]
  sum(apply(yp, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3]) > 2) })
cat(sprintf("  [음성 대조] 행 셔플 50회 n(t>+2): mean=%.1f q95=%.1f  vs 실측 %d\n",
            mean(nullc), quantile(nullc, .95), sum(fit[,"t"] > 2)))
ord <- order(fit[,"t"], decreasing = TRUE)
cat("  상위 8 (중복제거 후):\n")
for (i in ord[1:8]) cat(sprintf("    %-34s alpha=%+.3f%%/m t=%+.2f\n", idu[i], 100*fit[i,"alpha"], fit[i,"t"]))

cat("\n=== [3] 종목수 제약 실사 (Production Constraint: max 25) ===\n")
MP <- fromJSON(file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)
probe <- head(idu, 6); tot <- c()
for (sid in probe) {
  p <- file.path(PROJ, MP$modules[[sid]]$sim_result_path)
  s <- tryCatch(readRDS(p), error = function(e) NULL)
  if (is.null(s)) { cat(sprintf("  %-34s <load fail>\n", sid)); next }
  hn <- intersect(c("HOLDINGS", "holdings", "HOLDINGS_DT", "WEIGHTS"), names(s))
  if (!length(hn)) { cat(sprintf("  %-34s holdings 필드 없음 (fields: %s)\n", sid,
                                 paste(head(names(s), 8), collapse=","))); next }
  H <- as.data.table(s[[hn[1]]])
  tick <- intersect(c("Ticker","ticker","code","Code"), names(H))
  dcol <- intersect(c("Date","date","ym"), names(H))
  if (length(tick) && length(dcol)) {
    per <- H[, .N, by = c(dcol[1])]
    cat(sprintf("  %-34s holdings rows=%d  종목수/기간 median=%.0f max=%d\n",
                sid, nrow(H), median(per$N), max(per$N)))
    tot <- c(tot, median(per$N))
  } else cat(sprintf("  %-34s holdings cols=%s\n", sid, paste(names(H), collapse=",")))
}
if (length(tot)) cat(sprintf("  ⇒ 모듈 1개당 median 종목수 ~%.0f. K개 모듈 합성 시 합집합 상한 = K x %.0f (중복 제외 전).\n",
                             median(tot), median(tot)))
cat("  ★ 결론 축: NAV-레벨 모듈 앙상블은 종목수 max 25 를 자동 충족하지 않는다.\n")
cat("    ⇒ 본 라운드 산출은 **screen-tier 진단**으로 라벨하고, 자본 졸업 주장을 하지 않는다.\n")
cat("      자본 경로로 가려면 종목-레벨 재구성(합집합 -> top-25 재선별)이 별도 단계로 필요.\n")

write_json(list(
  n_modules = ncol(M), n_exact_groups = n_exact_groups, n_unique_vectors = length(tb),
  n_effective_independent = n_eff, reduction_pct = 100*(1-n_eff/ncol(M)),
  after_dedup = list(pc1 = ev[1]/sum(ev), eff_n = sum(ev)^2/sum(ev^2),
                     n_t_gt2 = sum(fit[,"t"]>2), n_t_lt2 = sum(fit[,"t"]< -2), n = nrow(fit),
                     null_mean = mean(nullc), null_q95 = as.numeric(quantile(nullc,.95))),
  holdings_median = if (length(tot)) median(tot) else NA,
  metric_type = "diagnostic_precheck"
), file.path(OUT, "p0f_dupcheck.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("\n[done]\n"); sink()
