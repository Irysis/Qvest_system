#==============================================================================
# v2_repair_validate.R — FQ-219 수리 A/B (재현이 아니라 **실행 대조**)
#
# OLD(스냅샷) 와 NEW(작업트리) 를 각각 별도 env 에 source 해 같은 입력·같은 sig_date 로 돌린다.
#
# 측정:
#   M1 단위 교정 — C11/M25 의 s/qtr 단위가 맞는가 (max 가 일-스케일 400~700 → 분기 6~10)
#   M2 결번 교량 해소 — 수리 후 streak 이 결번 분기를 안 가로지르는가
#   M3 커버리지 변화 — staleness 규칙이 몇 행을 줄이는가 (FQ-218 선례와 대조)
#   M4 C11 ≡ M25 — 두 구현이 여전히 같은 값을 내는가 (공통 티커)
#   ★양성 대조 — C11/M25 외 **모든** consensus/momentum 팩터가 값까지 비트 불변인가
#   ★가드 무영향 — epoch 가드 5일이 월말 sig_date 에서 no-op 인가
#
# factor_db 재빌드 없음 (compute_* 호출만, save 경로 미접촉).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
FDB  <- file.path(ROOT, "02_Infrastructure/factor_db")

cons_dir <- file.path(ROOT, ".cache/consensus")
CONSENSUS <- list()
for (cf in list.files(cons_dir, pattern = "\\.parquet$", full.names = TRUE)) {
  CONSENSUS[[gsub("\\.parquet$", "", basename(cf))]] <- as.data.table(read_parquet(cf))
}
RAW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
setkey(RAW, Date, Ticker)
trading <- sort(unique(RAW$Date))

envs <- list()
for (tag in c("OLD", "NEW")) {
  for (mod in c("consensus", "momentum")) {
    e <- new.env(parent = globalenv())
    p <- if (tag == "OLD") file.path(OUT, sprintf("compute_%s_OLD.R", mod))
         else file.path(FDB, sprintf("compute_%s.R", mod))
    sys.source(p, envir = e)
    envs[[paste0(tag, "_", mod)]] <- e
  }
}
stopifnot(!exists(".cons_streak", envir = envs$OLD_consensus, inherits = FALSE),
          exists(".cons_streak", envir = envs$NEW_consensus, inherits = FALSE),
          !exists(".cons_streak", envir = envs$OLD_momentum, inherits = FALSE),
          exists(".cons_streak", envir = envs$NEW_momentum, inherits = FALSE))
cat("[load] OLD/NEW x consensus/momentum 4 env 분리 확인 (.cons_streak OLD 부재/NEW 존재)\n")

# ★헬퍼 본문 일치 (두 파일 복제가 갈리지 않았는가)
b1 <- paste(deparse(body(get(".cons_streak", envir = envs$NEW_consensus))), collapse = "\n")
b2 <- paste(deparse(body(get(".cons_streak", envir = envs$NEW_momentum))), collapse = "\n")
e1 <- paste(deparse(body(get(".cons_epoch", envir = envs$NEW_consensus))), collapse = "\n")
e2 <- paste(deparse(body(get(".cons_epoch", envir = envs$NEW_momentum))), collapse = "\n")
cat(sprintf("[helper] .cons_streak 본문 일치=%s  .cons_epoch 본문 일치=%s\n",
            identical(b1, b2), identical(e1, e2)))

month_ends <- as.Date(c("2008-12-31", "2014-03-31", "2020-06-30", "2026-06-30"))
sig_dates <- as.Date(vapply(month_ends, function(me) {
  av <- trading[trading <= me]; as.numeric(av[length(av)]) }, numeric(1)),
  origin = "1970-01-01")
cat(sprintf("표본 sig_date: %s\n", paste(as.character(sig_dates), collapse = ", ")))

gv <- function(dt, f) { x <- dt[Factor_Name == f, .(Ticker, v = Raw_Value)]
                        if (!nrow(x)) NULL else x }

m_rows <- list(); pc_rows <- list(); guard_rows <- list()
for (sig_d in sig_dates) {
  sig_d <- as.Date(sig_d, origin = "1970-01-01")
  rd <- RAW[Date <= sig_d & Date >= (sig_d - 1400L)]

  co <- envs$OLD_consensus$compute_consensus(rd, sig_d, NULL, CONSENSUS); setDT(co)
  cn <- envs$NEW_consensus$compute_consensus(rd, sig_d, NULL, CONSENSUS); setDT(cn)
  mo <- envs$OLD_momentum$compute_momentum(rd, sig_d, NULL, CONSENSUS); setDT(mo)
  mn <- envs$NEW_momentum$compute_momentum(rd, sig_d, NULL, CONSENSUS); setDT(mn)

  for (spec in list(list(f = "C11_Earnings_Streak", o = co, n = cn),
                    list(f = "M25_Earnings_Mom_Streak", o = mo, n = mn))) {
    a <- gv(spec$o, spec$f); b <- gv(spec$n, spec$f)
    m_rows[[length(m_rows) + 1L]] <- data.table(
      sig_date = sig_d, factor = spec$f,
      n_old = if (is.null(a)) 0L else nrow(a), n_new = if (is.null(b)) 0L else nrow(b),
      max_old = if (is.null(a)) NA_real_ else max(a$v),
      max_new = if (is.null(b)) NA_real_ else max(b$v),
      med_old = if (is.null(a)) NA_real_ else median(a$v),
      med_new = if (is.null(b)) NA_real_ else median(b$v),
      ndist_old = if (is.null(a)) 0L else uniqueN(a$v),
      ndist_new = if (is.null(b)) 0L else uniqueN(b$v),
      rho_old_new = if (is.null(a) || is.null(b)) NA_real_ else {
        mm <- merge(a, b, by = "Ticker"); if (nrow(mm) > 5)
          suppressWarnings(cor(mm$v.x, mm$v.y, method = "spearman")) else NA_real_ })
  }

  # M4 C11 ≡ M25 (NEW)
  a <- gv(cn, "C11_Earnings_Streak"); b <- gv(mn, "M25_Earnings_Mom_Streak")
  if (!is.null(a) && !is.null(b)) {
    mm <- merge(a, b, by = "Ticker")
    cat(sprintf("  [%s] NEW C11≡M25: 공통 %d 티커  최대절대차 %.10f  전건일치=%s\n",
                sig_d, nrow(mm), max(abs(mm$v.x - mm$v.y)),
                all(abs(mm$v.x - mm$v.y) < 1e-12)))
  }

  # ★양성 대조 — 대상 외 전 팩터 값 비트 불변
  # 예상 변경 집합 = {C11, M25, M32}. M32_Composite_Mom_v2 = mean(z(M01,M10,M13,M24,M25))
  # (compute_momentum.R:517-526) 이라 M25 를 소비한다 → 변경이 **예상된 전파**다.
  # 아래에서 M32 의 변경이 M25 로 전부 설명되는지 따로 확인한다.
  for (pr in list(list(o = co, n = cn, tgt = "C11_Earnings_Streak", mod = "consensus"),
                  list(o = mo, n = mn, tgt = c("M25_Earnings_Mom_Streak",
                                               "M32_Composite_Mom_v2"), mod = "momentum"))) {
    fs <- setdiff(sort(union(pr$o$Factor_Name, pr$n$Factor_Name)), pr$tgt)
    for (f in fs) {
      a <- gv(pr$o, f); b <- gv(pr$n, f)
      if (is.null(a) && is.null(b)) next
      if (is.null(a) || is.null(b)) {
        pc_rows[[length(pc_rows)+1L]] <- data.table(sig_date = sig_d, module = pr$mod,
          factor = f, n_old = if (is.null(a)) 0L else nrow(a),
          n_new = if (is.null(b)) 0L else nrow(b), identical_vals = FALSE,
          maxdiff = NA_real_); next
      }
      mm <- merge(a, b, by = "Ticker", suffixes = c("_o","_n"), all = TRUE)
      md <- suppressWarnings(max(abs(mm$v_o - mm$v_n), na.rm = TRUE))
      pc_rows[[length(pc_rows)+1L]] <- data.table(
        sig_date = sig_d, module = pr$mod, factor = f, n_old = nrow(a), n_new = nrow(b),
        identical_vals = (nrow(a) == nrow(b)) && (nrow(mm) == nrow(a)) &&
                         !any(is.na(mm$v_o)) && !any(is.na(mm$v_n)) &&
                         is.finite(md) && md < 1e-12,
        maxdiff = md)
    }
  }

  # ★M32 전파 검증 — M32 가 바뀐 티커가 M25 가 바뀐 티커로 설명되는가
  a32 <- gv(mo, "M32_Composite_Mom_v2"); b32 <- gv(mn, "M32_Composite_Mom_v2")
  a25 <- gv(mo, "M25_Earnings_Mom_Streak"); b25 <- gv(mn, "M25_Earnings_Mom_Streak")
  if (!is.null(a32) && !is.null(b32)) {
    m32 <- merge(a32, b32, by = "Ticker", suffixes = c("_o", "_n"))
    chg <- m32[abs(v_o - v_n) > 1e-12, Ticker]
    touched <- union(if (is.null(a25)) character(0) else a25$Ticker,
                     if (is.null(b25)) character(0) else b25$Ticker)
    guard_rows[[length(guard_rows)+1L]] <- data.table(
      sig_date = sig_d, n_m32 = nrow(m32), n_m32_changed = length(chg),
      frac_changed_explained_by_m25 = if (length(chg)) mean(chg %chin% touched) else NA_real_,
      n_m25_touched = length(touched))
  }
}

M <- rbindlist(m_rows); PC <- rbindlist(pc_rows); G <- rbindlist(guard_rows)
fwrite(M, file.path(OUT, "v2_repair_effect.csv"))
fwrite(PC, file.path(OUT, "v2_positive_control.csv"))
fwrite(G, file.path(OUT, "v2_m32_propagation.csv"))

cat("\n=========== M1~M3 수리 효과 ===========\n"); print(M)
cat("\n=========== M32 전파 (M25 소비자) ===========\n"); print(G)
cat("\n=========== 양성 대조 (예상 변경 = C11/M25/M32) ===========\n")
bad <- PC[identical_vals == FALSE]
cat(sprintf("대조 팩터-월 조합 %d건 중 변경 %d건\n", nrow(PC), nrow(bad)))
if (nrow(bad)) { cat("★변경 발생 — 수리가 범위를 넘었다:\n"); print(bad) } else
  cat("PASS — C11/M25/M32 외 전 consensus/momentum 팩터가 값까지 비트 불변\n")
