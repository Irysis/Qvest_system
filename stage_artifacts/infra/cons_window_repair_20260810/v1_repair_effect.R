#==============================================================================
# v1_repair_effect.R — FQ-218 (B) 수리 효과 실측 + 양성 대조
#
# 진짜 A/B: git HEAD(수리 전) 파일과 작업트리(수리 후) 파일을 **각각 별도 env 에**
# source 해서 같은 입력·같은 sig_date 로 돌린다. 재현이 아니라 실행 대조다.
#
# 측정 (작업 명세 4지표):
#   1. C10/C13 의 mean==latest 비율  (= C01/C04 와 값이 같은 티커 비율)
#   2. C10↔C01 · C13↔C04 의 rho / maxdiff — 비트동일이 풀렸는가
#   3. C15 의 sd / 0값 비율 — 분산을 갖는가
#   4. 창 내 고유값 중앙
#
# ★양성 대조: C10/C13/C15 를 제외한 **모든** 컨센서스 팩터가 전후 불변인가.
#   (행수뿐 아니라 티커별 값까지 대조 — 행수만 보면 값이 바뀐 걸 놓친다.)
#
# factor_db 재빌드 없음 — 메모리 상 compute_consensus() 호출만(save 경로 미접촉).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

# ── 입력 로드 (빌더와 동일 경로) ───────────────────────────────────────────
cons_dir <- file.path(ROOT, ".cache/consensus")
CONSENSUS <- list()
for (cf in list.files(cons_dir, pattern = "\\.parquet$", full.names = TRUE)) {
  nm <- gsub("\\.parquet$", "", basename(cf))
  CONSENSUS[[nm]] <- as.data.table(read_parquet(cf))
}
cat(sprintf("CONSENSUS: %d tables (%s)\n", length(CONSENSUS),
            paste(names(CONSENSUS), collapse = ", ")))

RAW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
setkey(RAW, Date, Ticker)
cat(sprintf("RAWDATA: %s rows  %s .. %s\n", format(nrow(RAW), big.mark = ","),
            min(RAW$Date), max(RAW$Date)))
trading <- sort(unique(RAW$Date))

# ── 두 판본 로드 ───────────────────────────────────────────────────────────
env_old <- new.env(parent = globalenv())
env_new <- new.env(parent = globalenv())
sys.source(file.path(OUT, "compute_consensus_OLD.R"), envir = env_old)
sys.source(file.path(ROOT, "02_Infrastructure/factor_db/compute_consensus.R"),
           envir = env_new)
stopifnot(is.function(env_old$compute_consensus), is.function(env_new$compute_consensus))
stopifnot(!exists(".cons_quarters", envir = env_old, inherits = FALSE))
stopifnot(exists(".cons_quarters", envir = env_new, inherits = FALSE))
cat("[load] OLD/NEW 판본 분리 로드 확인 (.cons_quarters: OLD 부재 / NEW 존재)\n")

# ── 표본 월 (6개월 이상, 시대 분산) ────────────────────────────────────────
month_ends <- as.Date(c("2006-06-30", "2010-06-30", "2011-03-31", "2014-06-30",
                        "2018-06-30", "2019-09-30", "2022-06-30", "2024-06-30"))
sig_dates <- as.Date(vapply(seq_along(month_ends), function(i) {
  av <- trading[trading <= month_ends[i]]
  as.numeric(av[length(av)])
}, numeric(1)), origin = "1970-01-01")
cat(sprintf("표본 sig_date %d개: %s\n", length(sig_dates),
            paste(as.character(sig_dates), collapse = ", ")))

pair_rows <- list(); c15_rows <- list(); pc_rows <- list(); dist_rows <- list()

for (k in seq_along(sig_dates)) {
  sig_d <- sig_dates[k]
  rd <- RAW[Date <= sig_d & Date >= (sig_d - 1400L)]
  o <- env_old$compute_consensus(rd, sig_d, FUND = NULL, CONSENSUS = CONSENSUS)
  n <- env_new$compute_consensus(rd, sig_d, FUND = NULL, CONSENSUS = CONSENSUS)
  setDT(o); setDT(n)

  gv <- function(dt, f) {
    x <- dt[Factor_Name == f, .(Ticker, v = Raw_Value)]
    if (!nrow(x)) NULL else x
  }

  # ── 지표 1·2: C10↔C01, C13↔C04 ──
  for (pr in list(c("C10_SUE_Persistence", "C01_SUE"),
                  c("C13_Revision_Breadth_3m", "C04_ESBR"))) {
    for (tag in c("OLD", "NEW")) {
      dt <- if (tag == "OLD") o else n
      a <- gv(dt, pr[1]); b <- gv(dt, pr[2])
      if (is.null(a) || is.null(b)) {
        pair_rows[[length(pair_rows) + 1L]] <- data.table(
          version = tag, sig_date = sig_d, derived = pr[1], base = pr[2],
          n_derived = if (is.null(a)) 0L else nrow(a),
          n_common = 0L, frac_eq = NA_real_, rho = NA_real_, maxdiff = NA_real_)
        next
      }
      m <- merge(a, b, by = "Ticker", suffixes = c("_d", "_b"))
      pair_rows[[length(pair_rows) + 1L]] <- data.table(
        version = tag, sig_date = sig_d, derived = pr[1], base = pr[2],
        n_derived = nrow(a), n_common = nrow(m),
        frac_eq = mean(abs(m$v_d - m$v_b) < 1e-12),
        rho = if (nrow(m) > 2) suppressWarnings(
                cor(m$v_d, m$v_b, method = "spearman")) else NA_real_,
        maxdiff = max(abs(m$v_d - m$v_b)))
    }
  }

  # ── 지표 3: C15 분산 ──
  for (tag in c("OLD", "NEW")) {
    dt <- if (tag == "OLD") o else n
    x <- gv(dt, "C15_Forecast_Error_Trend")
    c15_rows[[length(c15_rows) + 1L]] <- data.table(
      version = tag, sig_date = sig_d,
      n_rows = if (is.null(x)) 0L else nrow(x),
      sd = if (is.null(x) || nrow(x) < 2) NA_real_ else sd(x$v),
      frac_zero = if (is.null(x)) NA_real_ else mean(abs(x$v) < 1e-12),
      n_distinct = if (is.null(x)) 0L else uniqueN(x$v))
  }

  # ── 지표 4: 창 내 고유값 (NEW 헬퍼 직접 호출) ──
  hist_sue  <- env_new$.cons_history(CONSENSUS, "sue", sig_d)
  hist_esbr <- env_new$.cons_history(CONSENSUS, "esbr", sig_d)
  for (spec in list(list(h = hist_sue, m = "sue", n = 4L, f = "C10"),
                    list(h = hist_esbr, m = "esbr", n = 3L, f = "C13"),
                    list(h = hist_sue, m = "sue", n = 2L, f = "C15"))) {
    if (is.null(spec$h)) next
    # OLD 창 = 최신 n 행
    ho <- copy(spec$h); setnames(ho, spec$m, "value")
    old_d <- ho[, .(nd = uniqueN(value[seq_len(min(.N, spec$n))]),
                    span = as.integer(Date[1L] - Date[min(.N, spec$n)])), by = Ticker]
    q <- env_new$.cons_quarters(spec$h, spec$m, sig_d, n_take = spec$n)
    new_d <- if (is.null(q)) NULL else
      q[, .(nd = uniqueN(value),
            span = as.integer(max(run_end) - min(run_start))), by = Ticker]
    dist_rows[[length(dist_rows) + 1L]] <- data.table(
      sig_date = sig_d, factor = spec$f, n_take = spec$n,
      old_median_distinct = median(old_d$nd), old_median_span = median(old_d$span),
      new_median_distinct = if (is.null(new_d)) NA_real_ else median(new_d$nd),
      new_median_span = if (is.null(new_d)) NA_real_ else median(new_d$span),
      old_n = nrow(old_d), new_n = if (is.null(new_d)) 0L else nrow(new_d))
  }

  # ── 양성 대조: C10/C13/C15 외 전 팩터 값까지 대조 ──
  target <- c("C10_SUE_Persistence", "C13_Revision_Breadth_3m",
              "C15_Forecast_Error_Trend")
  fs <- sort(union(o$Factor_Name, n$Factor_Name))
  for (f in setdiff(fs, target)) {
    a <- gv(o, f); b <- gv(n, f)
    if (is.null(a) && is.null(b)) next
    if (is.null(a) || is.null(b)) {
      pc_rows[[length(pc_rows) + 1L]] <- data.table(
        sig_date = sig_d, factor = f, n_old = if (is.null(a)) 0L else nrow(a),
        n_new = if (is.null(b)) 0L else nrow(b), identical_vals = FALSE,
        maxdiff = NA_real_); next
    }
    m <- merge(a, b, by = "Ticker", suffixes = c("_o", "_n"), all = TRUE)
    md <- suppressWarnings(max(abs(m$v_o - m$v_n), na.rm = TRUE))
    pc_rows[[length(pc_rows) + 1L]] <- data.table(
      sig_date = sig_d, factor = f, n_old = nrow(a), n_new = nrow(b),
      identical_vals = (nrow(a) == nrow(b)) && (nrow(m) == nrow(a)) &&
                       !any(is.na(m$v_o)) && !any(is.na(m$v_n)) &&
                       is.finite(md) && md < 1e-12,
      maxdiff = md)
  }
  cat(sprintf("  [%s] OLD %d행 / NEW %d행\n", sig_d, nrow(o), nrow(n)))
}

pr <- rbindlist(pair_rows); c15 <- rbindlist(c15_rows)
pc <- rbindlist(pc_rows); di <- rbindlist(dist_rows)
fwrite(pr,  file.path(OUT, "v1_pair_identity.csv"))
fwrite(c15, file.path(OUT, "v1_c15_variance.csv"))
fwrite(pc,  file.path(OUT, "v1_positive_control.csv"))
fwrite(di,  file.path(OUT, "v1_window_distinct.csv"))

cat("\n=========== 지표 1·2: 파생↔기저 동일성 ===========\n")
print(pr[, .(n_month = .N, n_derived = round(mean(n_derived)),
             frac_eq_latest = mean(frac_eq), rho = mean(rho),
             maxdiff = max(maxdiff)), by = .(derived, base, version)][order(derived, version)])
cat("\n=========== 지표 3: C15 분산 ===========\n")
print(c15[, .(n_month = .N, n_rows = round(mean(n_rows)), sd = mean(sd),
              frac_zero = mean(frac_zero), n_distinct = round(mean(n_distinct))),
          by = version])
cat("\n=========== 지표 4: 창 내 고유값 / span ===========\n")
print(di[, .(old_distinct = median(old_median_distinct),
             new_distinct = median(new_median_distinct),
             old_span = median(old_median_span), new_span = median(new_median_span),
             old_n = round(mean(old_n)), new_n = round(mean(new_n))), by = .(factor, n_take)])
cat("\n=========== 양성 대조: 무관 팩터 불변성 ===========\n")
bad <- pc[identical_vals == FALSE]
cat(sprintf("대조 팩터-월 조합 %d건 중 변경 %d건\n", nrow(pc), nrow(bad)))
if (nrow(bad)) { cat("★변경 발생 — 수리가 범위를 넘었다:\n"); print(bad) } else {
  cat("PASS — C10/C13/C15 외 전 팩터가 값까지 비트 불변\n")
  print(pc[, .(n_month = .N, n_old = round(mean(n_old)), n_new = round(mean(n_new)),
               max_maxdiff = max(maxdiff)), by = factor])
}
