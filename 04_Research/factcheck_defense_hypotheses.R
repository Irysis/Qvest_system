## ============================================================
## Defense 가설 팩트체크 — H1-R / H3-R
## Scout 재설계 가설 검증: ICIR, 상관, Alpha Lab Gate
## ============================================================
cat("=== Defense 가설 팩트체크 시작 ===\n")
cat("날짜:", as.character(Sys.Date()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 1. conditional_ic_matrix 로드 ──────────────────────────────
ic_path <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache/conditional_ic_matrix.csv")
ic_mat  <- fread(ic_path)
setnames(ic_mat, "Factor_Name", "factor_id")

# 검증 대상 팩터
h1r_factors  <- c("R01_VaR_95", "Q01_GPA")
h3r_factors  <- c("Q24_Altman_Z", "V05_fPBR", "L04_Bid_Ask_Proxy")
h2_factors   <- c("V14_EBIT_EV", "AC21_CF_to_Accrual_Ratio", "M25_Earnings_Mom_Streak")
str1555_fac  <- c("C19_Composite_Earnings")
all_focus    <- unique(c(h1r_factors, h3r_factors, h2_factors, str1555_fac))

cat("─────────────────────────────────────────────────────────\n")
cat("[1] conditional_ic_matrix 주요 지표\n")
cat("─────────────────────────────────────────────────────────\n")

sub <- ic_mat[factor_id %in% all_focus]
sub <- sub[, .(factor_id, ic_all, ic_bad, ic_good, conditional_value, recent_3y_icir, n_months, category)]
sub[, icir_abs  := abs(recent_3y_icir)]
sub[, alg_pass  := icir_abs >= 0.20]  # Alpha Lab Gate

# ic_bad > ic_good (defense 조건: 하락장에서 더 잘 작동)
sub[, def_cond  := ic_bad > ic_good]
# negative ic_bad with positive conditional_value => 하락장에서 낮은 값이 실제로 방어
sub[, cond_val_sign := sign(conditional_value)]

print(sub[order(factor_id)], row.names = FALSE)

cat("\n")
cat("─────────────────────────────────────────────────────────\n")
cat("[2] Alpha Lab Gate (ICIR ≥ 0.20) 통과 여부\n")
cat("─────────────────────────────────────────────────────────\n")

for (f in all_focus) {
  row <- sub[factor_id == f]
  if (nrow(row) == 0) {
    cat(sprintf("  %-30s : NOT FOUND\n", f))
    next
  }
  status <- ifelse(row$alg_pass, "PASS", "FAIL")
  cat(sprintf("  %-30s  ICIR=%+.3f  |%s|\n",
              f, row$recent_3y_icir, status))
}

cat("\n")
cat("─────────────────────────────────────────────────────────\n")
cat("[3] Defense 조건: ic_bad > ic_good (하락장 우위)\n")
cat("─────────────────────────────────────────────────────────\n")

for (f in c(h1r_factors, h3r_factors)) {
  row <- sub[factor_id == f]
  if (nrow(row) == 0) next
  def_ok  <- row$def_cond
  cat(sprintf("  %-30s  ic_bad=%+.4f  ic_good=%+.4f  cond_val=%+.4f  defense_cond=%s\n",
              f, row$ic_bad, row$ic_good, row$conditional_value,
              ifelse(def_ok, "YES", "NO")))
}

# ── 2. 팩터 간 상관 계산 (Factor DB 샘플 로드) ─────────────────
cat("\n")
cat("─────────────────────────────────────────────────────────\n")
cat("[4] 팩터 간 상관 계산 (Factor DB 최근 36개월)\n")
cat("─────────────────────────────────────────────────────────\n")

fdb_dir <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache/factor_db/")
fdb_files <- list.files(fdb_dir, pattern="^factor_db_2[0-9]{5}\\.parquet$", full.names=TRUE)
fdb_files <- sort(fdb_files)

# 최근 36개월만 (상관 계산용, 전기간 로드 불필요)
recent_files <- tail(fdb_files, 36)
cat(sprintf("  로드 파일 수: %d개 (%s ~ %s)\n",
            length(recent_files),
            basename(recent_files[1]),
            basename(tail(recent_files, 1))))

# 필요 팩터만 로드 (C15: load 시 필터)
need_cols <- c("Date", "Ticker", "Z_Score_Aligned",
               all_focus[all_focus %in% c(h1r_factors, h3r_factors,
                                           h2_factors, str1555_fac)])

load_fdb_factor <- function(files, factor_id_vec) {
  result_list <- vector("list", length(files))
  for (i in seq_along(files)) {
    tryCatch({
      dt <- as.data.table(read_parquet(files[i]))
      # Factor DB 컬럼: Factor_Name, Z_Score (Z_Score_Aligned 없음)
      if (!all(c("Date","Ticker","Factor_Name","Z_Score") %in% names(dt))) next
      sub_dt <- dt[Factor_Name %in% factor_id_vec, .(Date, Ticker, Factor_Name, Z_Score)]
      result_list[[i]] <- sub_dt
    }, error = function(e) NULL)
  }
  rbindlist(result_list, use.names=TRUE, fill=TRUE)
}

fdb_long <- load_fdb_factor(recent_files, all_focus)
cat(sprintf("  로드 완료: %d rows, %d unique factors\n",
            nrow(fdb_long), fdb_long[, uniqueN(Factor_Name)]))
cat(sprintf("  보유 팩터: %s\n",
            paste(sort(unique(fdb_long$Factor_Name)), collapse=", ")))

# Wide 변환 (종목×날짜 기준)
if (nrow(fdb_long) > 0) {
  fdb_wide <- dcast(fdb_long, Date + Ticker ~ Factor_Name,
                    value.var = "Z_Score", fun.aggregate = mean)
  setkey(fdb_wide, Date, Ticker)

  # 상관 계산용 — 종목 레벨 (cross-sectional pooled)
  cor_cols <- intersect(all_focus, names(fdb_wide))
  cat(sprintf("  상관 계산 가능 팩터: %s\n", paste(cor_cols, collapse=", ")))

  if (length(cor_cols) >= 2) {
    cor_data <- fdb_wide[, ..cor_cols]
    cor_data <- cor_data[complete.cases(cor_data)]
    cor_mat  <- cor(cor_data, use = "complete.obs", method = "spearman")

    cat("\n  [상관 행렬 — Spearman, 최근 36개월 pooled]\n")
    print(round(cor_mat, 3))

    cat("\n")
    cat("─────────────────────────────────────────────────────────\n")
    cat("[4a] H1-R 내부 상관 (R01 ↔ Q01)\n")
    cat("─────────────────────────────────────────────────────────\n")
    if (all(c("R01_VaR_95","Q01_GPA") %in% cor_cols)) {
      r <- cor_mat["R01_VaR_95","Q01_GPA"]
      cat(sprintf("  R01_VaR_95 vs Q01_GPA : rho = %+.3f\n", r))
      cat(sprintf("  판정: %s\n", ifelse(abs(r) < 0.3, "독립적 (OK)", ifelse(abs(r) < 0.5, "약한 상관", "중복 위험"))))
    }

    cat("\n")
    cat("─────────────────────────────────────────────────────────\n")
    cat("[4b] H3-R 내부 상관 (Q24 ↔ V05, Q24 ↔ L04, V05 ↔ L04)\n")
    cat("─────────────────────────────────────────────────────────\n")
    pairs3 <- list(c("Q24_Altman_Z","V05_fPBR"),
                   c("Q24_Altman_Z","L04_Bid_Ask_Proxy"),
                   c("V05_fPBR",    "L04_Bid_Ask_Proxy"))
    for (p in pairs3) {
      if (all(p %in% cor_cols)) {
        r <- cor_mat[p[1], p[2]]
        cat(sprintf("  %-25s vs %-25s : rho = %+.3f  %s\n",
                    p[1], p[2], r,
                    ifelse(abs(r) < 0.3, "(독립)", ifelse(abs(r) < 0.5, "(약상관)", "(중복주의)"))))
      }
    }

    cat("\n")
    cat("─────────────────────────────────────────────────────────\n")
    cat("[4c] H2(V14/AC21/M25)와의 상관 — V05 vs V14 특히 주의\n")
    cat("─────────────────────────────────────────────────────────\n")
    cross_pairs <- list(
      c("V05_fPBR",         "V14_EBIT_EV"),
      c("V05_fPBR",         "AC21_CF_to_Accrual_Ratio"),
      c("V05_fPBR",         "M25_Earnings_Mom_Streak"),
      c("Q24_Altman_Z",     "V14_EBIT_EV"),
      c("Q24_Altman_Z",     "AC21_CF_to_Accrual_Ratio"),
      c("L04_Bid_Ask_Proxy","V14_EBIT_EV"),
      c("R01_VaR_95",       "V14_EBIT_EV"),
      c("Q01_GPA",          "V14_EBIT_EV"),
      c("Q01_GPA",          "AC21_CF_to_Accrual_Ratio")
    )
    for (p in cross_pairs) {
      if (all(p %in% cor_cols)) {
        r <- cor_mat[p[1], p[2]]
        flag <- ifelse(abs(r) >= 0.5, " <== 중복 경고", "")
        cat(sprintf("  %-30s vs %-30s : rho = %+.3f%s\n", p[1], p[2], r, flag))
      }
    }

    cat("\n")
    cat("─────────────────────────────────────────────────────────\n")
    cat("[4d] STR_1555 프록시(C19_Composite_Earnings)와의 상관\n")
    cat("─────────────────────────────────────────────────────────\n")
    str1555_cross <- c(h1r_factors, h3r_factors)
    for (f in str1555_cross) {
      if (all(c(f,"C19_Composite_Earnings") %in% cor_cols)) {
        r <- cor_mat[f, "C19_Composite_Earnings"]
        flag <- ifelse(abs(r) >= 0.5, " <== 중복 경고", "")
        cat(sprintf("  %-30s vs C19_Composite_Earnings : rho = %+.3f%s\n", f, r, flag))
      }
    }
  }
}

# ── 3. 종합 판정 ──────────────────────────────────────────────
cat("\n")
cat("=================================================================\n")
cat("[5] 종합 판정 (Alpha Lab Gate + Defense 조건 + 상관)\n")
cat("=================================================================\n")

# H1-R 판정
cat("\n[H1-R] R01_VaR_95 + Q01_GPA (defense)\n")
r01 <- sub[factor_id == "R01_VaR_95"]
q01 <- sub[factor_id == "Q01_GPA"]

cat(sprintf("  R01_VaR_95: ICIR=%+.3f (%s)  ic_bad>ic_good=%s  cond_val=%+.4f\n",
            r01$recent_3y_icir,
            ifelse(abs(r01$recent_3y_icir)>=0.20,"PASS","FAIL"),
            r01$def_cond,
            r01$conditional_value))
cat(sprintf("  Q01_GPA   : ICIR=%+.3f (%s)  ic_bad>ic_good=%s  cond_val=%+.4f\n",
            q01$recent_3y_icir,
            ifelse(abs(q01$recent_3y_icir)>=0.20,"PASS","FAIL"),
            q01$def_cond,
            q01$conditional_value))

h1r_alg <- abs(r01$recent_3y_icir)>=0.20 & abs(q01$recent_3y_icir)>=0.20
h1r_def <- r01$def_cond & q01$def_cond

# R01은 음수 ICIR → 방향 주의
r01_dir_note <- ifelse(r01$recent_3y_icir < 0,
  "  !! R01 ICIR 음수: Z_Score_Aligned 방향 확인 필요 (고VaR = 위험, 음수 IC = 위험 종목 underperform → defense 로직 성립 가능)\n",
  "")
cat(r01_dir_note)

if (!h1r_alg) {
  cat("  --> BLOCK: Alpha Lab Gate ICIR < 0.20 (최소 1개 미달)\n")
  cat(sprintf("      R01: |%.3f| %s 0.20, Q01: |%.3f| %s 0.20\n",
              abs(r01$recent_3y_icir), ifelse(abs(r01$recent_3y_icir)>=0.20,">=","<"),
              abs(q01$recent_3y_icir), ifelse(abs(q01$recent_3y_icir)>=0.20,">=","<")))
} else if (!h1r_def) {
  cat("  --> CAUTION: defense 조건(ic_bad>ic_good) 불완전\n")
} else {
  cat("  --> GO\n")
}

# H3-R 판정
cat("\n[H3-R] Q24_Altman_Z + V05_fPBR + L04_Bid_Ask_Proxy (defense)\n")
q24 <- sub[factor_id == "Q24_Altman_Z"]
v05 <- sub[factor_id == "V05_fPBR"]
l04 <- sub[factor_id == "L04_Bid_Ask_Proxy"]

cat(sprintf("  Q24_Altman_Z   : ICIR=%+.3f (%s)  ic_bad>ic_good=%s  cond_val=%+.4f\n",
            q24$recent_3y_icir,
            ifelse(abs(q24$recent_3y_icir)>=0.20,"PASS","FAIL"),
            q24$def_cond,
            q24$conditional_value))
cat(sprintf("  V05_fPBR       : ICIR=%+.3f (%s)  ic_bad>ic_good=%s  cond_val=%+.4f\n",
            v05$recent_3y_icir,
            ifelse(abs(v05$recent_3y_icir)>=0.20,"PASS","FAIL"),
            v05$def_cond,
            v05$conditional_value))
cat(sprintf("  L04_Bid_Ask_Proxy: ICIR=%+.3f (%s)  ic_bad>ic_good=%s  cond_val=%+.4f\n",
            l04$recent_3y_icir,
            ifelse(abs(l04$recent_3y_icir)>=0.20,"PASS","FAIL"),
            l04$def_cond,
            l04$conditional_value))

h3r_alg <- abs(q24$recent_3y_icir)>=0.20 | abs(v05$recent_3y_icir)>=0.20 | abs(l04$recent_3y_icir)>=0.20
# 전체 ALG: 모든 팩터가 통과해야 하는지 / 앵커 팩터만?
h3r_alg_all <- abs(q24$recent_3y_icir)>=0.20 & abs(v05$recent_3y_icir)>=0.20 & abs(l04$recent_3y_icir)>=0.20

if (!h3r_alg) {
  cat("  --> BLOCK: 모든 팩터 Alpha Lab Gate 미달\n")
} else if (!h3r_alg_all) {
  cat("  --> CAUTION: 일부 팩터 ICIR < 0.20\n")
  for (f in c("Q24_Altman_Z","V05_fPBR","L04_Bid_Ask_Proxy")) {
    row <- sub[factor_id == f]
    status <- ifelse(abs(row$recent_3y_icir)>=0.20,"PASS","FAIL")
    cat(sprintf("      %s: |%.3f| = %s\n", f, abs(row$recent_3y_icir), status))
  }
} else {
  cat("  --> GO\n")
}

cat("\n=== 팩트체크 완료 ===\n")
