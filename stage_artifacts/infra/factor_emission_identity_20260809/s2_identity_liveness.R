## S2 — 정체 축 + 살아있음 축 (같은 실행에서 산출)
##   입력: 기존 factor_db 월 parquet (읽기만, 재빌드 없음)
##   경로: load_month_factors() 경유 (C15) · factor_dup_scan.R 의 행렬 빌더 재사용
##
##   축2 정체 : 월별 횡단면 spearman 최대값 + 최대절대차 → rho>=0.999 또는 maxdiff==0 = 중복 배출
##   축3 살아있음: sd == 0 또는 0값 비율 >= 0.99 = 죽은 배출
##   ★양성 대조(M26/C01 등 정상 팩터) · 음성 대조(C10=C01, C13=C04 기확정) 를 같은 실행에서 채점
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s2] ", fmt, "\n"), ...)); flush.console() }
t0 <- Sys.time()

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/factor_dup_scan.R")

## 표본월: 시대를 가르는 6개 (월말 거래일 근사 — 커넥터가 월 파일을 잡는다)
MONTHS <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30",
                    "2018-06-30", "2022-06-30", "2026-06-30"))

led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))

## ── 월별 패널 로드 → 존재/살아있음/정체 원자료 ────────────────────────────
live_rows <- list(); rho_max <- list(); panels <- list()
for (d in MONTHS) {
  d <- as.Date(d, origin = "1970-01-01")
  ym <- format(d, "%Y%m")
  z <- load_month_factors(d, coverage_min = 0)
  zt <- as.data.table(z)
  asof <- attr(z, "factor_db_asof_date"); fil <- attr(z, "factor_db_file")
  say("%s → file=%s asof=%s · 행 %s · 커넥터 가시 팩터 %d · 종목 %d",
      ym, fil, as.character(asof), format(nrow(zt), big.mark = ","),
      uniqueN(zt$Factor_Name), uniqueN(zt$Ticker))

  ## 커넥터 가시 vs 원장 배출 (Z 전건 NA/미커버 → 소비면에서 사라진다)
  ym_file <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", fil)
  led_set <- led[ym == ym_file & n_rows > 0, unique(Factor_Name)]
  invis <- sort(setdiff(led_set, unique(zt$Factor_Name)))
  say("   원장 배출 %d종 중 커넥터 비가시 %d종%s", length(led_set), length(invis),
      if (length(invis)) sprintf(" → %s", paste(invis, collapse = ", ")) else "")

  ## 살아있음 축 (값 = Z_Score_Aligned; 횡단면 단조변환이라 sd=0 / 상수는 보존)
  lv <- zt[, .(n_obs = .N,
               sd_val = sd(Z_Score_Aligned, na.rm = TRUE),
               zero_frac = mean(Z_Score_Aligned == 0, na.rm = TRUE),
               n_uniq = uniqueN(round(Z_Score_Aligned, 12))), by = Factor_Name]
  lv[, ym := ym]
  live_rows[[ym]] <- lv

  ## 정체 축 원자료 — 랭크 변환 wide 행렬 (spearman-on-common-support)
  W <- dcast(zt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  M <- as.matrix(W[, -1L, with = FALSE]); rownames(M) <- W$Ticker
  panels[[ym]] <- M
}
live <- rbindlist(live_rows)
fwrite(live, file.path(OUT, "s2_liveness_by_factor_month.csv"))
say("패널 로드 완료 %.1fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))

## ── 축3 판정: 죽은 배출 ───────────────────────────────────────────────────
dead <- live[, .(n_months = .N,
                 min_sd = min(sd_val, na.rm = TRUE), max_sd = max(sd_val, na.rm = TRUE),
                 max_zero_frac = max(zero_frac, na.rm = TRUE),
                 min_uniq = min(n_uniq), med_obs = as.numeric(median(n_obs))), by = Factor_Name]
dead[, dead_flag := (max_sd == 0 | is.na(max_sd)) | (max_zero_frac >= 0.99) | min_uniq <= 1L]
say("=== 축3 살아있음 ===")
say("검사 팩터 %d · 죽은 배출 후보 %d", nrow(dead), dead[dead_flag == TRUE, .N])
if (dead[dead_flag == TRUE, .N]) print(dead[dead_flag == TRUE][order(Factor_Name)])
## 상수-근접(전월 아니고 일부 월만) 도 기록
partial <- live[sd_val == 0 | n_uniq <= 1L | zero_frac >= 0.99]
say("월-단위 상수/무분산 셀 %d개 (팩터 %d종)", nrow(partial), uniqueN(partial$Factor_Name))
if (nrow(partial)) print(partial[order(Factor_Name, ym)][1:min(40, .N)])
fwrite(dead, file.path(OUT, "s2_dead_verdict.csv"))
fwrite(partial, file.path(OUT, "s2_constant_cells.csv"))

## ── 축2 판정: 정체 (전 팩터 × 전 팩터, 월별 spearman 최대값) ───────────────
grid <- sort(unique(unlist(lapply(panels, colnames))))
ng <- length(grid)
say("=== 축2 정체 === grid %d팩터 · 쌍 %s", ng, format(ng * (ng - 1) / 2, big.mark = ","))
rank_mat <- function(M) {
  cn <- colnames(M); rn <- rownames(M)
  R <- vapply(seq_len(ncol(M)), function(j) {
    v <- M[, j]; r <- rep(NA_real_, length(v)); k <- !is.na(v)
    if (any(k)) r[k] <- rank(v[k], ties.method = "average"); r
  }, numeric(nrow(M)))
  matrix(R, ncol = length(cn), dimnames = list(rn, cn))
}
MIN_OBS <- 30L
best <- matrix(NA_real_, ng, ng, dimnames = list(grid, grid))   # 월별 |rho| 최대
nmax <- matrix(0L, ng, ng, dimnames = list(grid, grid))
signed_at_best <- matrix(NA_real_, ng, ng, dimnames = list(grid, grid))
for (ym in names(panels)) {
  M <- panels[[ym]]
  keep <- intersect(colnames(M), grid)
  R <- rank_mat(M[, keep, drop = FALSE])
  C <- suppressWarnings(stats::cor(R, use = "pairwise.complete.obs"))
  A <- !is.na(R); storage.mode(A) <- "integer"; N <- crossprod(A)
  C[N < MIN_OBS] <- NA_real_
  Cb <- best[keep, keep]; Sb <- signed_at_best[keep, keep]; Nb <- nmax[keep, keep]
  upd <- !is.na(C) & (is.na(Cb) | abs(C) > Cb)
  Cb[upd] <- abs(C)[upd]; Sb[upd] <- C[upd]; Nb[upd] <- N[upd]
  best[keep, keep] <- Cb; signed_at_best[keep, keep] <- Sb; nmax[keep, keep] <- Nb
  say("  %s spearman 격자 완료 (%.1fs 누적)", ym, as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
ut <- upper.tri(best)
idx <- which(ut & !is.na(best) & best >= 0.99, arr.ind = TRUE)
pairs <- data.table(factor_a = grid[idx[, 1]], factor_b = grid[idx[, 2]],
                    max_abs_spearman = best[idx], signed = signed_at_best[idx],
                    n_common = nmax[idx])
setorder(pairs, -max_abs_spearman)
say("|spearman| >= 0.99 쌍 %d개 (>=0.999: %d)", nrow(pairs), pairs[max_abs_spearman >= 0.999, .N])

## 후보 쌍만 정확 재측정: 월별 exact spearman + 최대절대차 (공통 support)
cand <- pairs[max_abs_spearman >= 0.99]
detail <- rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  a <- cand$factor_a[i]; b <- cand$factor_b[i]
  rbindlist(lapply(names(panels), function(ym) {
    M <- panels[[ym]]
    if (!all(c(a, b) %in% colnames(M))) return(NULL)
    x <- M[, a]; y <- M[, b]; k <- is.finite(x) & is.finite(y)
    if (sum(k) < MIN_OBS) return(NULL)
    data.table(ym = ym, factor_a = a, factor_b = b, n = sum(k),
               exact_equal_frac = mean(x[k] == y[k]),
               max_abs_diff = max(abs(x[k] - y[k])),
               spearman = suppressWarnings(cor(x[k], y[k], method = "spearman")))
  }))
}))
fwrite(detail, file.path(OUT, "s2_identity_pair_months.csv"))
summ <- detail[, .(n_months = .N,
                   min_spearman = min(spearman), max_spearman = max(spearman),
                   med_spearman = as.numeric(median(spearman)),
                   min_exact_equal = min(exact_equal_frac),
                   max_exact_equal = max(exact_equal_frac),
                   max_of_maxdiff = max(max_abs_diff),
                   min_of_maxdiff = min(max_abs_diff)), by = .(factor_a, factor_b)]
summ[, verdict := fifelse(min_exact_equal >= 0.999 & max_of_maxdiff == 0, "DUP_EXACT_BITWISE",
              fifelse(max_spearman >= 0.999 | min_spearman <= -0.999, "DUP_RANK_IDENTICAL",
                                              "NEAR_DUP_0.99"))]
setorder(summ, -max_spearman)
say("=== 정체 판정 ===")
print(summ)
fwrite(summ, file.path(OUT, "s2_identity_verdict.csv"))

## ── 대조군 채점 (같은 실행) ───────────────────────────────────────────────
say("=== 음성 대조 (기확정 중복을 검사기가 잡는가) ===")
NEG <- list(c("C01_SUE", "C10_SUE_Persistence"), c("C04_ESBR", "C13_Revision_Breadth_3m"))
for (p in NEG) {
  hit <- summ[(factor_a == p[1] & factor_b == p[2]) | (factor_a == p[2] & factor_b == p[1])]
  if (nrow(hit)) say("  검거 O: %s ~ %s → %s (max_spearman %.6f · maxdiff %.3e)",
                     p[1], p[2], hit$verdict[1], hit$max_spearman[1], hit$max_of_maxdiff[1])
  else say("  ★검거 X: %s ~ %s 가 후보에 없음 → 검사기 무효", p[1], p[2])
}
say("=== 양성 대조 (정상 팩터가 정상으로 분류되는가) ===")
POS <- c("M26_Revenue_Mom", "C01_SUE", "V01_BM", "M01_Mom12_1", "S01_Size", "Q07_ROE")
for (f in POS) {
  in_dup <- summ[factor_a == f | factor_b == f, .N]
  dd <- dead[Factor_Name == f]
  if (!nrow(dd)) { say("  %s: 패널 부재 (판정 불가)", f); next }
  say("  %-18s 중복쌍 %d · dead_flag %s · sd범위 [%.4f, %.4f] · 0값비율 max %.4f · 월수 %d",
      f, in_dup, dd$dead_flag[1], dd$min_sd[1], dd$max_sd[1], dd$max_zero_frac[1], dd$n_months[1])
}
say("총 소요 %.1fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))
say("완료")
