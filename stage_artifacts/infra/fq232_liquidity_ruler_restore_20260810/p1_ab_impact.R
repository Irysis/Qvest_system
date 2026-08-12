## FQ-232 P1 — 기본동작 parity + 자 복원 A/B 영향 실측 (본체)
##  (d) 기본 동작 변화 여부: 수리 전(git) 판본 vs 수리 후 default 호출 = 동일해야 함
##  (c) 영향 실측: DEGRADED(월말 1일치) vs 복원(20일 평균 t-1) — 통과 종목·멤버십·PORT_t
##  ★M26 필수 포함 (FQ-161 +1.544 재산출)
##  ★계측 생존(양성 대조): 유동성 문턱을 극단으로 바꾸면 멤버십이 실제로 바뀌는가
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq232_liquidity_ruler_restore_20260810")
SC  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/731a7a86-b8bf-4640-9de7-b5e7830e4ad8/scratchpad"
say <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
t00 <- Sys.time()

## ── 0. 입력 실측 (첫 출력) ───────────────────────────────────────────────────
RAWPATH <- ".cache/RAWDATA.parquet"; fi <- file.info(RAWPATH)
say("vintage pin: %s | %.0f bytes | mtime %s", RAWPATH, fi$size, format(fi$mtime))
RAW <- as.data.table(read_parquet(RAWPATH,
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("★입력 실측 RAW: %d행 · %d 거래일 · 관측단위=일간(월당 중앙 %.0f일)",
    nrow(RAW), uniqueN(RAW$Date),
    median(as.integer(table(format(sort(unique(RAW$Date)), "%Y-%m")))))
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)

## ── 1. 자 2벌 준비 ───────────────────────────────────────────────────────────
suppressMessages(source("02_Infrastructure/ramp/factor_validation.R"))
ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAW[Date %in% ME]; rm(RAW); invisible(gc(FALSE))
say("slim RAWME %d행 · ADV20 %d행 (월말 앵커 %d)", nrow(RAWME), nrow(ADV20), length(ME))

## ── 2. (d) 기본 동작 parity — 수리 전 판본 vs 수리 후 default ────────────────
say("=== (d) 기본 동작 무변경 검증 ===")
say("수리 전 판본 소스: %s", file.path(SC, "fv_old.R"))
suppressMessages(suppressWarnings(source(file.path(SC, "fv_old.R"))))
say("  old 시그니처: build_monthly_forward_returns(%s)",
    paste(names(formals(build_monthly_forward_returns)), collapse = ", "))
fwd_old <- suppressWarnings(build_monthly_forward_returns(RAWME, ME))
suppressMessages(source("02_Infrastructure/ramp/factor_validation.R"))   # 수리 후 재로드
say("  new 시그니처: build_monthly_forward_returns(%s)",
    paste(names(formals(build_monthly_forward_returns)), collapse = ", "))
fwd_deg <- suppressWarnings(build_monthly_forward_returns(RAWME, ME))    # default = 무인자
cmp_par <- list(
  returns_identical = isTRUE(all.equal(fwd_old$returns_dt, fwd_deg$returns_dt)),
  bench_identical   = isTRUE(all.equal(fwd_old$bench_dt,   fwd_deg$bench_dt)),
  liq_identical     = isTRUE(all.equal(as.data.frame(fwd_old$liq_dt), as.data.frame(fwd_deg$liq_dt))),
  ruler_old = fwd_old$liq_ruler, ruler_new = fwd_deg$liq_ruler,
  firewall_identical = identical(fwd_old$ret_firewall_dropped, fwd_deg$ret_firewall_dropped))
say("  returns 동일=%s · bench 동일=%s · liq 동일=%s · firewall 동일=%s",
    cmp_par$returns_identical, cmp_par$bench_identical, cmp_par$liq_identical,
    cmp_par$firewall_identical)
say("  자 라벨: old='%s' → new='%s' (source=%s)",
    cmp_par$ruler_old, cmp_par$ruler_new, fwd_deg$liq_ruler_source %||% "NA")

## ── 3. 복원 호출 ─────────────────────────────────────────────────────────────
say("=== 자 복원 호출 (liq_daily = ADV20) ===")
fwd_res <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
say("  liq_ruler='%s' source='%s' · returns 동일=%s · bench 동일=%s",
    fwd_res$liq_ruler, fwd_res$liq_ruler_source,
    isTRUE(all.equal(fwd_deg$returns_dt, fwd_res$returns_dt)),
    isTRUE(all.equal(fwd_deg$bench_dt,   fwd_res$bench_dt)))
LIQ_DEG <- fwd_deg$liq_dt; LIQ_RES <- fwd_res$liq_dt
say("  attr 도달: deg='%s' / res='%s'",
    attr(LIQ_DEG, "liq_ruler"), attr(LIQ_RES, "liq_ruler"))

## ── 4. 두 자 대조 (전 유니버스 종-월) ────────────────────────────────────────
CMP <- merge(LIQ_DEG[, .(Date, Ticker, adv_deg = adv)],
             LIQ_RES[, .(Date, Ticker, adv_res = adv)], by = c("Date","Ticker"), all = TRUE)
LIQ_MIN <- 2e8
CMP[, `:=`(pass_deg = !is.na(adv_deg) & adv_deg >= LIQ_MIN | is.na(adv_deg),
           pass_res = !is.na(adv_res) & adv_res >= LIQ_MIN | is.na(adv_res))]
ruler_cmp <- list(
  n = nrow(CMP),
  pass_deg = sum(CMP$pass_deg), pass_res = sum(CMP$pass_res),
  only_deg = sum(CMP$pass_deg & !CMP$pass_res), only_res = sum(!CMP$pass_deg & CMP$pass_res),
  disagree_pct = 100 * mean(CMP$pass_deg != CMP$pass_res),
  na_deg = sum(is.na(CMP$adv_deg)), na_res = sum(is.na(CMP$adv_res)),
  pearson = suppressWarnings(cor(CMP$adv_deg, CMP$adv_res, use = "complete.obs")),
  spearman = suppressWarnings(cor(CMP$adv_deg, CMP$adv_res, use = "complete.obs", method = "spearman")))
say("=== 두 자 대조 (전 유니버스 %d 종-월) ===", ruler_cmp$n)
say("  통과: DEGRADED %d → 복원 %d (순 %+d, %+.3f%%p)", ruler_cmp$pass_deg, ruler_cmp$pass_res,
    ruler_cmp$pass_res - ruler_cmp$pass_deg,
    100 * (ruler_cmp$pass_res - ruler_cmp$pass_deg) / ruler_cmp$n)
say("  DEGRADED만 통과 %d · 복원만 통과 %d · 판정 불일치 %.3f%%",
    ruler_cmp$only_deg, ruler_cmp$only_res, ruler_cmp$disagree_pct)
say("  adv NA: deg %d · res %d | pearson %.4f · spearman %.4f",
    ruler_cmp$na_deg, ruler_cmp$na_res, ruler_cmp$pearson, ruler_cmp$spearman)
fwrite(CMP[, .(Date, Ticker, adv_deg, adv_res, pass_deg, pass_res)],
       file.path(OUT, "p1_ruler_pair_universe.csv.gz"), compress = "gzip")

## ── 5. M26 점수 패널 ─────────────────────────────────────────────────────────
A <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/WT_D20260808_002/alpha_scores.parquet")))
A[, Date := as.Date(Date)]
say("★입력 실측 alpha_scores: %d행 · %d개월 · %s~%s", nrow(A), uniqueN(A$Date),
    min(A$signal_ym), max(A$signal_ym))
S_raw <- A[, .(Date, Ticker, score = M26_Revenue_Mom)]
A[, resid := { fit <- lm(M26_Revenue_Mom ~ C01_SUE + C02_EPS_Chg_1m + C04_ESBR)
               as.numeric(residuals(fit)) }, by = signal_ym]
S_res <- A[, .(Date, Ticker, score = resid)]
size_dt <- RAWME[, .(Date, Ticker, Size)]
ret <- fwd_deg$returns_dt; bench <- fwd_deg$bench_dt   # 자와 무관 (동일 확인 완료)

## ── 6. 멤버십 복제기 (canonical 내부 선별과 동일 절차) ───────────────────────
##   ★복제가 맞는지 가정하지 않는다: 복제 멤버십으로 만든 gross 월수익이
##     canonical 의 ret_net + cost 와 일치하는지 실측으로 검증한다(아래 verify).
sel_members <- function(S, LIQ, liq_min = LIQ_MIN, top_n = 25L) {
  X <- as.data.table(S)[!is.na(score)]
  if (!is.null(LIQ)) {
    X <- merge(X, as.data.table(LIQ)[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
    X <- X[is.na(adv) | adv >= liq_min]; X[, adv := NULL]
  }
  setorder(X, Date, -score)
  X[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
}

run_canon <- function(S, LIQ, tag, liq_min = LIQ_MIN, top_n = 25L) {
  r <- suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = top_n, cost_bps_oneway = 15,
        liq_dt = LIQ, liq_min = liq_min,
        run_id = paste0("FQ232_", tag), strategy_id = paste0("M26_", tag),
        diag_dual_basis = TRUE, size_dt = size_dt))
  say("  [%s] PORT_t=%+.4f · ruler=%s(%s) · n_months=%d · net_sr=%.4f · TO=%.2f",
      tag, r$portfolio_alpha_t_nw_lag3 %||% NA_real_, r$liq_ruler %||% "NA",
      r$liq_ruler_source %||% "NA", r$n_months %||% NA, r$net_sr %||% NA_real_,
      r$turnover_annual %||% NA_real_)
  lf <- r$liq_filter
  if (!is.null(lf)) say("      liq_filter: before %d → after %d (drop %d, NA통과 %d, min %.3g)",
                        lf$n_before, lf$n_after, lf$n_dropped, lf$n_na_pass, lf$liq_min)
  r
}

say("=== (c) M26 전이 재산출 ===")
suppressMessages(source("02_Infrastructure/contracts/canonical_screen_bt.R"))
R_raw_deg <- run_canon(S_raw, LIQ_DEG, "raw_DEGRADED")
R_raw_res <- run_canon(S_raw, LIQ_RES, "raw_RESTORED")
R_res_deg <- run_canon(S_res, LIQ_DEG, "resid_DEGRADED")
R_res_res <- run_canon(S_res, LIQ_RES, "resid_RESTORED")

## 멤버십 복제 검증 (계측 생존 1) — 복제 gross 가 canonical 과 일치하는가
verify_repl <- function(canon, S, LIQ, tag) {
  W <- sel_members(S, LIQ)
  WR <- merge(W, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  g <- WR[, .(gross = sum(w * Ret_1m)), by = Date]
  pr <- as.data.table(canon$period_returns)
  ## canonical: ret_net = gross - cost. cost 는 turnover 기반이라 여기선 gross 만 대조 불가 →
  ## 대신 canonical 내부와 동일 절차로 cost 를 재구성해 ret_net 을 만들어 대조한다.
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  g[, ret_net := gross - traded[as.character(Date)] * 15 / 1e4]
  M <- merge(g[, .(date = Date, ret_net_repl = ret_net)], pr[, .(date, ret_net)], by = "date")
  mx <- max(abs(M$ret_net_repl - M$ret_net))
  say("  [복제검증 %s] n=%d · max|Δret_net| = %.3g → %s", tag, nrow(M), mx,
      if (mx < 1e-12) "복제 = canonical 선별과 동일" else "★불일치 — 복제기 무효")
  list(n = nrow(M), max_abs_diff = mx, ok = mx < 1e-12, W = W)
}
V_deg <- verify_repl(R_raw_deg, S_raw, LIQ_DEG, "raw_DEGRADED")
V_res <- verify_repl(R_raw_res, S_raw, LIQ_RES, "raw_RESTORED")

## ── 7. 멤버십 변화 ───────────────────────────────────────────────────────────
memb_delta <- function(Wa, Wb) {
  a <- Wa[, .(set = list(sort(Ticker))), by = Date]; b <- Wb[, .(set = list(sort(Ticker))), by = Date]
  m <- merge(a, b, by = "Date", suffixes = c("_a","_b"))
  m[, `:=`(n_a = lengths(set_a), n_b = lengths(set_b),
           n_common = mapply(function(x, y) length(intersect(x, y)), set_a, set_b))]
  m[, `:=`(n_changed = pmax(n_a, n_b) - n_common,
           jaccard = mapply(function(x, y) length(intersect(x, y)) / length(union(x, y)), set_a, set_b))]
  m[, .(Date, n_a, n_b, n_common, n_changed, jaccard)]
}
MD <- memb_delta(V_deg$W, V_res$W)
say("=== 멤버십 변화 (top-25, M26 원신호) ===")
say("  %d개월 중 변동월 %d (%.1f%%) · 평균 교체 %.3f 종목/월 · 최대 %d · 평균 jaccard %.4f",
    nrow(MD), sum(MD$n_changed > 0), 100 * mean(MD$n_changed > 0), mean(MD$n_changed),
    max(MD$n_changed), mean(MD$jaccard))
say("  월별 선정수: deg 중앙 %d(min %d) · res 중앙 %d(min %d)",
    median(MD$n_a), min(MD$n_a), median(MD$n_b), min(MD$n_b))
fwrite(MD, file.path(OUT, "p1_membership_delta_m26raw.csv"))

## 통과 종목 수 (점수 패널 한정, 월별)
PB <- merge(A[, .(Date, Ticker)], CMP[, .(Date, Ticker, pass_deg, pass_res)],
            by = c("Date","Ticker"), all.x = TRUE)
PB[is.na(pass_deg), pass_deg := TRUE]; PB[is.na(pass_res), pass_res := TRUE]
PM <- PB[, .(n_univ = .N, n_deg = sum(pass_deg), n_res = sum(pass_res)), by = Date][order(Date)]
say("=== 통과 종목 수 (M26 점수 패널 %d 종-월) ===", nrow(PB))
say("  월평균 유니버스 %.1f · DEGRADED 통과 %.1f · 복원 통과 %.1f (Δ %+.2f/월)",
    mean(PM$n_univ), mean(PM$n_deg), mean(PM$n_res), mean(PM$n_res - PM$n_deg))
say("  통과수 다른 달 %d/%d (%.1f%%)", sum(PM$n_deg != PM$n_res), nrow(PM),
    100 * mean(PM$n_deg != PM$n_res))
fwrite(PM, file.path(OUT, "p1_pass_counts_by_month.csv"))

## ── 8. 양성 대조 (계측 생존) + 무관축 불변 대조 ──────────────────────────────
say("=== 양성 대조: 문턱 극단 변경이 멤버십을 바꾸는가 ===")
W_ext <- sel_members(S_raw, LIQ_RES, liq_min = 1e12)
MD_ext <- memb_delta(V_res$W, W_ext)
say("  liq_min 2e8 → 1e12: 변동월 %d/%d (%.1f%%) · 평균 교체 %.2f · 평균 jaccard %.3f",
    sum(MD_ext$n_changed > 0), nrow(MD_ext), 100 * mean(MD_ext$n_changed > 0),
    mean(MD_ext$n_changed), mean(MD_ext$jaccard))
W_zero <- sel_members(S_raw, LIQ_RES, liq_min = 0)
MD_zero <- memb_delta(W_zero, sel_members(S_raw, NULL))
say("  liq_min 0 vs 무필터: 변동월 %d (0이어야 정상)", sum(MD_zero$n_changed > 0))
R_ext <- run_canon(S_raw, LIQ_RES, "raw_RESTORED_liqmin1e12", liq_min = 1e12)
say("=== 무관축 불변 대조: 종목수 제약(top_n=25) ===")
say("  선정 종목수 max: deg %d · res %d · 극단 %d (전부 <= 25 여야 함)",
    max(MD$n_a), max(MD$n_b), max(MD_ext$n_b))

## ── 9. 요약 ──────────────────────────────────────────────────────────────────
summ <- data.table(
  arm = c("raw_DEGRADED","raw_RESTORED","resid_DEGRADED","resid_RESTORED","raw_RESTORED_liq1e12"),
  ruler = c(R_raw_deg$liq_ruler, R_raw_res$liq_ruler, R_res_deg$liq_ruler, R_res_res$liq_ruler,
            R_ext$liq_ruler),
  port_t = c(R_raw_deg$portfolio_alpha_t_nw_lag3, R_raw_res$portfolio_alpha_t_nw_lag3,
             R_res_deg$portfolio_alpha_t_nw_lag3, R_res_res$portfolio_alpha_t_nw_lag3,
             R_ext$portfolio_alpha_t_nw_lag3),
  net_sr = c(R_raw_deg$net_sr, R_raw_res$net_sr, R_res_deg$net_sr, R_res_res$net_sr, R_ext$net_sr),
  ir     = c(R_raw_deg$information_ratio, R_raw_res$information_ratio, R_res_deg$information_ratio,
             R_res_res$information_ratio, R_ext$information_ratio),
  n_months = c(R_raw_deg$n_months, R_raw_res$n_months, R_res_deg$n_months, R_res_res$n_months,
               R_ext$n_months),
  turnover = c(R_raw_deg$turnover_annual, R_raw_res$turnover_annual, R_res_deg$turnover_annual,
               R_res_res$turnover_annual, R_ext$turnover_annual))
print(summ)
say("★M26 원신호: FQ-161 기록 +1.5441 · 본 라운드 DEGRADED %+.4f (parity Δ %+.6f) → 복원 %+.4f (Δ %+.4f)",
    summ$port_t[1], summ$port_t[1] - 1.544110, summ$port_t[2], summ$port_t[2] - summ$port_t[1])
fwrite(summ, file.path(OUT, "p1_arm_summary.csv"))

saveRDS(list(parity = cmp_par, ruler_cmp = ruler_cmp, summ = summ,
             memb = MD, memb_ext = MD_ext, pass_month = PM,
             verify_repl = list(deg = V_deg[c("n","max_abs_diff","ok")],
                                res = V_res[c("n","max_abs_diff","ok")]),
             vintage = list(path = RAWPATH, bytes = fi$size, mtime = format(fi$mtime))),
        file.path(OUT, "p1_results.rds"))
say("총 소요 %.1fs", as.numeric(difftime(Sys.time(), t00, units = "secs")))
