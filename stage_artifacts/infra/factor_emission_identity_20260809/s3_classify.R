## S3 — 분류 + 대조군 정식화
##  (1) 축3 재설계: sd(Z)=1 은 표준화의 항등 결과라 **검사로서 죽어 있다**.
##      살아있는 통계 = 최빈값 점유율(modal_frac) + 고유값 비율 + 커넥터 비가시
##  (2) 축2 139쌍을 registry `dedup` 선언과 대조 → 기선언(관리중) vs 미선언(신규 적발)
##  (3) 양성/음성 대조를 **위반 주입**으로 정식화
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s3] ", fmt, "\n"), ...)); flush.console() }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

MONTHS <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30",
                    "2018-06-30", "2022-06-30", "2026-06-30"))
led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)

## ── 패널 재로드 (읽기만) ──────────────────────────────────────────────────
panels <- list(); vis <- list()
for (d in MONTHS) {
  d <- as.Date(d, origin = "1970-01-01")
  z <- as.data.table(load_month_factors(d, coverage_min = 0))
  fil <- attr(load_month_factors(d, coverage_min = 0, factor_names = "C01_SUE"), "factor_db_file")
  ymf <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", fil)
  W <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  M <- as.matrix(W[, -1L, with = FALSE]); rownames(M) <- W$Ticker
  panels[[ymf]] <- M
  vis[[ymf]] <- unique(z$Factor_Name)
}
YMS <- names(panels)
say("패널 %s", paste(YMS, collapse = " "))

##==========================================================================
## 축3 (재설계) — 살아있음
##==========================================================================
## 3a) 원장 배출 > 0 인데 커넥터 비가시 = 전건 NA/무분산 배출 (raw sd=0 등가)
inv <- rbindlist(lapply(YMS, function(y) {
  ls_ <- led[ym == y & n_rows > 0, .(Factor_Name, n_rows, n_tickers)]
  ls_[!Factor_Name %in% vis[[y]]][, ym := y]
}))
invs <- inv[, .(n_months_invisible = .N, yms = paste(ym, collapse = ","),
                med_rows = as.numeric(median(n_rows)),
                med_tickers = as.numeric(median(n_tickers))), by = Factor_Name]
invs[, n_months_emitted := sapply(Factor_Name, function(f) sum(sapply(YMS, function(y) f %in% led[ym == y & n_rows > 0, Factor_Name])))]
invs[, always_invisible := n_months_invisible == n_months_emitted]
setorder(invs, -n_months_invisible, Factor_Name)
say("=== 축3a: 원장 배출 O · 커넥터 비가시 (전건 NA/무분산) ===")
print(invs)

## 3b) 커넥터 가시분의 최빈값 점유율 / 고유값 비율 — 준-죽은 배출
lv <- rbindlist(lapply(YMS, function(y) {
  M <- panels[[y]]
  rbindlist(lapply(colnames(M), function(f) {
    v <- M[, f]; v <- v[is.finite(v)]
    if (!length(v)) return(data.table(ym = y, Factor_Name = f, n_obs = 0L, sd_z = NA_real_,
                                      modal_frac = NA_real_, uniq_ratio = NA_real_, zero_frac = NA_real_))
    tb <- table(round(v, 10))
    data.table(ym = y, Factor_Name = f, n_obs = length(v), sd_z = sd(v),
               modal_frac = max(tb) / length(v), uniq_ratio = length(tb) / length(v),
               zero_frac = mean(v == 0))
  }))
}))
fwrite(lv, file.path(OUT, "s3_liveness_stats.csv"))
say("=== 축3b: 살아있음 통계 (커넥터 가시분) ===")
say("sd(Z) 범위 [%.6f, %.6f] — ★표준화 항등이라 판별력 0 (검사로 쓸 수 없음)",
    min(lv$sd_z, na.rm = TRUE), max(lv$sd_z, na.rm = TRUE))
say("modal_frac 범위 [%.4f, %.4f] · uniq_ratio 범위 [%.4f, %.4f]",
    min(lv$modal_frac, na.rm = TRUE), max(lv$modal_frac, na.rm = TRUE),
    min(lv$uniq_ratio, na.rm = TRUE), max(lv$uniq_ratio, na.rm = TRUE))
agg <- lv[, .(n_months = .N, max_modal = max(modal_frac), min_uniq = min(uniq_ratio),
              max_zero = max(zero_frac)), by = Factor_Name]
agg[, quasi_dead := max_modal >= 0.99 | max_zero >= 0.99]
say("modal_frac >= 0.99 (준-죽은 배출): %d종", agg[quasi_dead == TRUE, .N])
if (agg[quasi_dead == TRUE, .N]) print(agg[quasi_dead == TRUE][order(-max_modal)])
say("modal_frac 상위 12 (경계 확인):")
print(head(agg[order(-max_modal)], 12))
fwrite(agg, file.path(OUT, "s3_liveness_verdict.csv"))

##==========================================================================
## 축2 분류 — registry dedup 선언 대조
##==========================================================================
dd <- rbindlist(lapply(names(reg), function(k) data.table(
  Factor_Name = k,
  role      = as.character(reg[[k]]$dedup$role %||% NA_character_)[1],
  canonical = as.character(reg[[k]]$dedup$canonical %||% NA_character_)[1],
  cluster   = as.character(reg[[k]]$dedup$cluster %||% NA_character_)[1])))
pv <- fread(file.path(OUT, "s2_identity_verdict.csv"))
pv <- merge(pv, dd[, .(factor_a = Factor_Name, role_a = role, cluster_a = cluster, canon_a = canonical)],
            by = "factor_a", all.x = TRUE)
pv <- merge(pv, dd[, .(factor_b = Factor_Name, role_b = role, cluster_b = cluster, canon_b = canonical)],
            by = "factor_b", all.x = TRUE)
pv[, declared := fifelse(!is.na(cluster_a) & !is.na(cluster_b) & cluster_a == cluster_b, "DECLARED_SAME_CLUSTER",
                  fifelse(!is.na(canon_a) & canon_a == factor_b, "DECLARED_ALIAS",
                   fifelse(!is.na(canon_b) & canon_b == factor_a, "DECLARED_ALIAS", "UNDECLARED")))]
setorder(pv, -max_spearman)
say("=== 축2 정체: 선언 대조 ===")
print(pv[, .N, by = .(verdict, declared)][order(verdict, declared)])
say("--- 미선언 EXACT/RANK 중복 (신규 적발, 정본 지정 필요) ---")
und <- pv[declared == "UNDECLARED" & verdict != "NEAR_DUP_0.99"]
print(und[, .(factor_a, factor_b, verdict, max_spearman, min_spearman,
              max_of_maxdiff, min_exact_equal, cluster_a, cluster_b)])
fwrite(pv, file.path(OUT, "s3_identity_classified.csv"))

##==========================================================================
## 대조군 — 위반 주입 + 양성 대조 (같은 실행)
##==========================================================================
say("=== 위반 주입 테스트 (검사기가 진짜 위반을 잡는가) ===")
M <- panels[[YMS[length(YMS)]]]
base_f <- "M26_Revenue_Mom"
stopifnot(base_f %in% colnames(M))
inj_dup   <- M[, base_f]                       # ① 비트-동일 복제
inj_mono  <- exp(M[, base_f])                  # ② 단조변환(순위 동일, 값 다름)
inj_const <- rep(0, nrow(M))                   # ③ 전건 0 = 죽은 배출
inj_mode  <- c(rep(0, floor(nrow(M) * 0.995)), M[seq_len(nrow(M) - floor(nrow(M) * 0.995)), base_f])
chk_ident <- function(x, y) {
  k <- is.finite(x) & is.finite(y)
  list(rho = suppressWarnings(cor(x[k], y[k], method = "spearman")),
       maxdiff = max(abs(x[k] - y[k])), n = sum(k))
}
r1 <- chk_ident(M[, base_f], inj_dup)
r2 <- chk_ident(M[, base_f], inj_mono)
say("  ① 비트-동일 복제  → rho %.6f · maxdiff %.3e → 검거 %s", r1$rho, r1$maxdiff,
    if (abs(r1$rho) >= 0.999 || r1$maxdiff == 0) "O" else "★X")
say("  ② 단조변환 복제   → rho %.6f · maxdiff %.3e → 검거 %s", r2$rho, r2$maxdiff,
    if (abs(r2$rho) >= 0.999) "O" else "★X (maxdiff 단독으로는 못 잡음)")
mf <- function(v) { v <- v[is.finite(v)]; max(table(round(v, 10))) / length(v) }
say("  ③ 전건 0 배출     → sd %.6f · modal_frac %.4f · 검거 %s", sd(inj_const), mf(inj_const),
    if (mf(inj_const) >= 0.99) "O" else "★X")
say("  ④ 99.5%% 동일값   → modal_frac %.4f · 검거 %s", mf(inj_mode),
    if (mf(inj_mode) >= 0.99) "O" else "★X")
say("  ⑤ (음성대조) 실제 정상 팩터 modal_frac 최대 %.4f → 오검거 %s",
    max(agg$max_modal), if (max(agg$max_modal) >= 0.99) "★있음" else "없음")

say("=== 양성 대조: 정상 팩터가 정상으로 분류되는가 ===")
POS <- c("M26_Revenue_Mom", "V01_BM", "M01_Mom_12_1", "Q02_ROE", "L01_Turnover", "C18_Earnings_CAR_3d")
for (f in POS) {
  if (!f %in% agg$Factor_Name) { say("  %-24s 패널 부재", f); next }
  a <- agg[Factor_Name == f]
  nd <- pv[(factor_a == f | factor_b == f) & verdict != "NEAR_DUP_0.99", .N]
  say("  %-24s dup쌍(EXACT/RANK) %d · quasi_dead %s · max_modal %.4f · min_uniq %.4f",
      f, nd, a$quasi_dead[1], a$max_modal[1], a$min_uniq[1])
}
## C15 = 축3 음성 대조 (기확정 죽은 배출)
c15 <- invs[Factor_Name == "C15_Forecast_Error_Trend"]
say("=== 축3 음성 대조: C15_Forecast_Error_Trend ===")
if (nrow(c15)) {
  say("  검거 O — 비가시 %d/%d 월 (%s) · 원장 med_rows %.0f",
      c15$n_months_invisible, c15$n_months_emitted, c15$yms, c15$med_rows)
} else {
  say("  ★검거 X — 검사기 무효")
}
fwrite(invs, file.path(OUT, "s3_invisible_verdict.csv"))
say("=== 축3a 전체 목록 (배출 O · 소비면 비가시) ===")
for (i in seq_len(nrow(invs))) with(invs[i], say(
  "  %-32s 비가시 %d/%d월 · med_rows %.0f · med_tickers %.0f · always=%s",
  Factor_Name, n_months_invisible, n_months_emitted, med_rows, med_tickers, always_invisible))
say("완료")
