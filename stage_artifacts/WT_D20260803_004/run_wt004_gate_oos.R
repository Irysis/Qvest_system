# =============================================================================
# run_wt004_gate_oos.R — WT-D20260803_004 (FQ-121) 조합 자격 게이트 IS/OOS 분리 검증
#   사전등록: stage_artifacts/WT_D20260803_004/preregistration.json (측정 전 고정)
#   split    : IS = 2001-12-28~2014-02-28 (147m) / OOS = 2014-03-31~2026-06-30 (148m)
#   gate     : 성분 자격 = IS canonical PORT_t > 0 (OOS 일절 미조회)
#   arms(OOS): A1_GATE_IS / A2_POS2 / A3_ALL5 / A4_SINGLE_IS
#   판별     : (a) t(A1−A3) >= +2.0  (b) t(A1−A4) — 진짜 관문
#   위반주입 : LEAK_GATE(OOS PORT_t>0 게이트) / LEAK_SINGLE(OOS argmax)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_004/run_wt004_gate_oos.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_004")
IN9  <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt004] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()

TUNED_F <- c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB")
IS_END  <- as.Date("2014-02-28")   # 사전등록 고정 — 변경 금지

# ── 1. 하네스 (WT-021 동일 vintage 재현) ─────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet(file.path(IN9, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
n_is <- sum(SIG <= IS_END); n_oos <- sum(SIG > IS_END)
say("harness: SIG %d개월 | IS %d (~%s) / OOS %d (%s~)", length(SIG), n_is, IS_END,
    n_oos, min(SIG[SIG > IS_END]))
stopifnot(n_is == 147L, n_oos == 148L)   # 사전등록 정합

score_of <- function(fname) {
  sc <- if (fname %in% BASE$Factor_Name) BASE[Factor_Name == fname, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == fname, .(Date, Ticker, score = score)]
  merge(sc, UNIV, by = c("Date", "Ticker"))
}
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
canon <- function(sc, tag, dual = FALSE, feat = NULL) {
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260803_004", strategy_id = paste0("WT_D20260803_004_", tag),
    diag_dual_basis = dual, size_dt = if (dual) size_dt else NULL,
    ast_features = feat)
}

# ── 2. 성분 IS 게이트 (OOS 일절 미조회) + 성분 OOS 실측(위반주입 준비·별도 보관) ──
comp_is <- comp_oos <- list()
for (f in TUNED_F) {
  s <- score_of(f)[!is.na(score)]
  comp_is[[f]]  <- canon(s[Date <= IS_END], paste0("COMP_IS_", f))
  comp_oos[[f]] <- canon(s[Date >  IS_END], paste0("COMP_OOS_", f))
}
COMP <- data.table(Factor = TUNED_F,
  is_port_t  = sapply(TUNED_F, function(f) comp_is[[f]]$portfolio_alpha_t_nw_lag3),
  oos_port_t = sapply(TUNED_F, function(f) comp_oos[[f]]$portfolio_alpha_t_nw_lag3))
COMP[, is_pass  := is_port_t  > 0]
COMP[, oos_pass := oos_port_t > 0]
COMP[, borderline := abs(is_port_t) < 0.5]
COMP[, transfer_sign_stable := sign(is_port_t) == sign(oos_port_t)]
say("성분 게이트 표 (IS 자격 판정 / OOS는 위반주입 전용):")
print(COMP)
PASS_IS  <- COMP[is_pass  == TRUE, Factor]
PASS_OOS <- COMP[oos_pass == TRUE, Factor]
SINGLE_IS_F  <- COMP[which.max(is_port_t),  Factor]
SINGLE_OOS_F <- COMP[which.max(oos_port_t), Factor]
say("IS 통과 %d개: %s | IS argmax 단일: %s", length(PASS_IS),
    paste(PASS_IS, collapse = "+"), SINGLE_IS_F)

# ── 3. 합성 구축 (WT-021 build_zl 동일 규칙) ─────────────────────────────────
build_zl <- function(fnames) {
  zl <- rbindlist(lapply(fnames, function(f) {
    s <- score_of(f)
    s[, z := as.numeric(scale(score)), by = Date]
    s[, .(Date, Ticker, Factor_Name = f, z)]
  }))
  cov <- zl[!is.na(z), .N, by = .(Date, Factor_Name)]
  zl <- merge(zl, cov, by = c("Date", "Factor_Name"))
  zl[N >= 100L][, N := NULL]
}
composite_of <- function(fnames, min_nf) {
  if (length(fnames) == 1L) return(score_of(fnames)[!is.na(score), .(Date, Ticker, score)])
  zl <- build_zl(fnames)
  zl[!is.na(z), {
    if (.N >= min_nf) .(score = mean(z)) else .(score = NA_real_)
  }, by = .(Date, Ticker)][!is.na(score), .(Date, Ticker, score)]
}
SC_GATE <- composite_of(PASS_IS, min_nf = min(2L, length(PASS_IS)))
SC_POS2 <- composite_of(c("M01_PATHQ", "V01_SECREL"), min_nf = 2L)
SC_ALL5 <- composite_of(TUNED_F, min_nf = 3L)          # WT-015 C1 동일 규칙
SC_S_IS <- score_of(SINGLE_IS_F)[!is.na(score), .(Date, Ticker, score)]

# ── 4. OOS arm canonical 실측 ────────────────────────────────────────────────
FEAT_A1 <- list(node_count = 2L + 2L * length(PASS_IS), max_depth = 3,
  free_param_count = 0, distinct_field_count = length(PASS_IS),
  conditional_op_count = 0, window_variety = length(PASS_IS),
  restatement_exposure = 0, escape_leaf_count = length(PASS_IS),
  escape_leaf_types = list("STORED_SCORE"),
  note = "IS-gated EW composite of WT-009 tuned panel factors (FQ-121 OOS validation)")
A1 <- canon(SC_GATE[Date > IS_END], "A1_GATE_IS", dual = TRUE, feat = FEAT_A1)
A2 <- canon(SC_POS2[Date > IS_END], "A2_POS2")
A3 <- canon(SC_ALL5[Date > IS_END], "A3_ALL5")
A4 <- canon(SC_S_IS[Date > IS_END], "A4_SINGLE_IS", dual = TRUE)
arm_line <- function(a, nm) say("%s: PORT_t=%+.3f netSR=%+.3f TO=%.2f/yr n=%d cov=%.4f",
  nm, a$portfolio_alpha_t_nw_lag3, a$net_sr, a$turnover_annual, a$n_months,
  a$selected_ret_coverage)
arm_line(A1, "A1_GATE_IS"); arm_line(A2, "A2_POS2")
arm_line(A3, "A3_ALL5");    arm_line(A4, "A4_SINGLE_IS")

paired <- function(ax, ay) {
  m <- merge(as.data.table(ax$period_returns)[, .(date, x = ret_net)],
             as.data.table(ay$period_returns)[, .(date, y = ret_net)], by = "date")
  m[, d := x - y]
  list(t = nw_t(m$d), ann_pct = 100 * mean(m$d) * 12, n = nrow(m), d_series = m)
}
P_a  <- paired(A1, A3)   # (a) 게이트 유효성
P_b  <- paired(A1, A4)   # (b) 조합 존재 이유 — 진짜 관문
P_32 <- paired(A1, A2)   # POS3(게이트 전량) vs POS2
say("(a) A1−A3: NW t=%+.2f (%+.2f%%/yr)", P_a$t, P_a$ann_pct)
say("(b) A1−A4: NW t=%+.2f (%+.2f%%/yr)", P_b$t, P_b$ann_pct)
say("A1−A2   : NW t=%+.2f (%+.2f%%/yr)", P_32$t, P_32$ann_pct)

# ── 5. 위반 주입 (누출 게이트 — 게이트 실효 검증 전용, 채택 근거 사용 금지) ──
leak_same_gate <- identical(sort(PASS_OOS), sort(PASS_IS))
LK_G <- if (leak_same_gate) A1 else {
  canon(composite_of(PASS_OOS, min_nf = min(2L, length(PASS_OOS)))[Date > IS_END], "LEAK_GATE")
}
LK_S <- if (SINGLE_OOS_F == SINGLE_IS_F) A4 else {
  canon(score_of(SINGLE_OOS_F)[!is.na(score), .(Date, Ticker, score)][Date > IS_END], "LEAK_SINGLE")
}
say("주입: OOS-게이트 집합 %s (IS와 %s) | OOS argmax %s (IS와 %s)",
    paste(PASS_OOS, collapse = "+"), ifelse(leak_same_gate, "동일", "상이"),
    SINGLE_OOS_F, ifelse(SINGLE_OOS_F == SINGLE_IS_F, "동일", "상이"))
say("주입: LEAK_GATE PORT_t=%+.3f vs A1 %+.3f | LEAK_SINGLE %+.3f vs A4 %+.3f",
    LK_G$portfolio_alpha_t_nw_lag3, A1$portfolio_alpha_t_nw_lag3,
    LK_S$portfolio_alpha_t_nw_lag3, A4$portfolio_alpha_t_nw_lag3)

# ── 6. 강건성 — lag1 / placebo(fast path + parity gate) / AX-001 ─────────────
# lag1: 신호 1개월 지연 (Date_i에 Date_{i-1} 신호 적용)
lag1_scores <- function(sc) {
  d <- sort(unique(sc$Date))
  mp <- data.table(Date = d[-1], src = d[-length(d)])
  merge(mp, sc, by.x = "src", by.y = "Date", allow.cartesian = TRUE
        )[, .(Date, Ticker, score)]
}
A1_LAG <- canon(lag1_scores(SC_GATE)[Date > IS_END], "A1_LAG1")
say("lag1: A1_LAG PORT_t=%+.3f (base %+.3f) — 붕괴 시 동월 누출 의심",
    A1_LAG$portfolio_alpha_t_nw_lag3, A1$portfolio_alpha_t_nw_lag3)

# fast path (WT-021 동일) + parity gate on A3
select_top <- function(sc, top_n = 25L) {
  S <- as.data.table(sc)[!is.na(score)]
  S <- merge(S, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(top_n, .N)
        .(Ticker = Ticker[seq_len(n)], w = rep(1 / n, n)) }, by = Date]
}
port_from_w <- function(W, cost_bps = 15) {
  WR <- merge(W, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur", "_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, ret_net := port_gross - traded * cost_bps / 1e4]
  setorder(port, Date)
  port
}
FP_A3 <- port_from_w(select_top(SC_ALL5[Date > IS_END]))
par_m <- merge(FP_A3[, .(date = Date, mine = ret_net)],
               as.data.table(A3$period_returns)[, .(date, canon = ret_net)], by = "date")
par_err <- max(abs(par_m$mine - par_m$canon))
say("PARITY(fast path vs canonical, A3 OOS): %.2e (gate < 1e-8)", par_err)
stopifnot(par_err < 1e-8)

# placebo: A1 합성 score 월내 순열 20 draw (fast path — parity 검증 완료)
set.seed(20260803L)
SC_G_OOS <- SC_GATE[Date > IS_END]
bm_l <- bench_dt[, .(Date, BM_Ret)]
plc <- sapply(seq_len(20L), function(i) {
  sp <- copy(SC_G_OOS)[, score := sample(score), by = Date]
  p <- port_from_w(select_top(sp))
  p <- merge(p, bm_l, by = "Date")
  nw_t(p$ret_net - p$BM_Ret)
})
say("placebo(20): PORT_t mean %+.3f sd %.3f | max %+.3f | share |t|>=2: %.2f",
    mean(plc), sd(plc), max(plc), mean(abs(plc) >= 2))

# AX-001 조건부 (advisory): bad = BM_Ret < 0 월
ax001 <- function(a) {
  p <- as.data.table(a$period_returns)
  p[, act := ret_net - benchmark_ret]
  p[, bad := benchmark_ret < 0]
  c(bad_mean = 100 * p[bad == TRUE, mean(act)], normal_mean = 100 * p[bad == FALSE, mean(act)],
    n_bad = p[, sum(bad)])
}
ax_a1 <- ax001(A1); ax_a4 <- ax001(A4)
say("AX-001: A1 bad %+.3f%%/m normal %+.3f%%/m | A4 bad %+.3f%%/m normal %+.3f%%/m (n_bad=%d)",
    ax_a1["bad_mean"], ax_a1["normal_mean"], ax_a4["bad_mean"], ax_a4["normal_mean"],
    as.integer(ax_a1["n_bad"]))

# ── 7. 차트 (텔레그램 첨부용) ────────────────────────────────────────────────
dir.create(file.path(OUT, "charts"), showWarnings = FALSE)
arms_pr <- list(A1_GATE_IS = A1, A2_POS2 = A2, A3_ALL5 = A3, A4_SINGLE_IS = A4)
png(file.path(OUT, "charts", "wt004_oos_cum_active.png"), width = 1100, height = 620)
cols <- c(A1_GATE_IS = "#1f6feb", A2_POS2 = "#8250df", A3_ALL5 = "#cf222e",
          A4_SINGLE_IS = "#116329")
cum_l <- lapply(arms_pr, function(a) {
  p <- as.data.table(a$period_returns)
  p[, cum_act := cumsum(ret_net - benchmark_ret)]
  p
})
yl <- range(unlist(lapply(cum_l, function(p) 100 * p$cum_act)))
first <- TRUE
for (nm in names(cum_l)) {
  p <- cum_l[[nm]]
  if (first) {
    plot(p$date, 100 * p$cum_act, type = "l", lwd = 2, col = cols[nm],
         xlab = "OOS (2014-03 ~ 2026-06)", ylab = "누적 net active (%, 단리 합)",
         main = "WT-004 OOS 누적 초과수익 — 게이트 조합 vs 대조군",
         ylim = yl + c(-5, 5))
    first <- FALSE
  } else lines(p$date, 100 * p$cum_act, lwd = 2, col = cols[nm])
}
abline(h = 0, lty = 3)
legend("topleft", legend = sprintf("%s (PORT_t %+.2f)", names(arms_pr),
       sapply(arms_pr, function(a) a$portfolio_alpha_t_nw_lag3)),
       col = cols[names(arms_pr)], lwd = 2, bty = "n")
dev.off()

png(file.path(OUT, "charts", "wt004_paired_t.png"), width = 1100, height = 620)
tv <- c(`(a) 게이트−무게이트\nA1−A3` = P_a$t, `(b) 게이트−단일최강\nA1−A4` = P_b$t,
        `POS3−POS2\nA1−A2` = P_32$t)
bp <- barplot(tv, col = ifelse(tv >= 2, "#116329", ifelse(tv > 0, "#9a6700", "#cf222e")),
        ylab = "paired NW t (OOS)", main = "WT-004 사전등록 판별 — paired NW t",
        ylim = c(min(0, min(tv)) - 0.5, max(2.5, max(tv) + 0.5)))
abline(h = c(0, 2), lty = c(1, 2)); text(bp, tv, sprintf("%+.2f", tv), pos = 3)
dev.off()

# ── 8. 저장 ─────────────────────────────────────────────────────────────────
sc_after <- ast_sidecar_status()
slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(
  split = list(is_end = IS_END, n_is = n_is, n_oos = n_oos),
  components = COMP,
  pass_is = PASS_IS, pass_oos = PASS_OOS,
  single_is = SINGLE_IS_F, single_oos = SINGLE_OOS_F,
  arms = lapply(arms_pr, slim),
  paired = list(a_gate_vs_all5 = P_a[c("t", "ann_pct", "n")],
                b_gate_vs_single = P_b[c("t", "ann_pct", "n")],
                pos3_vs_pos2 = P_32[c("t", "ann_pct", "n")]),
  injection = list(leak_gate = slim(LK_G), leak_single = slim(LK_S),
                   same_gate_set = leak_same_gate,
                   same_single = SINGLE_OOS_F == SINGLE_IS_F),
  lag1 = slim(A1_LAG),
  parity_fastpath = par_err,
  placebo = list(draws = plc, mean = mean(plc), sd = sd(plc),
                 share_ge2 = mean(abs(plc) >= 2)),
  ax001 = list(A1 = ax_a1, A4 = ax_a4),
  d_series = list(a = P_a$d_series, b = P_b$d_series),
  sidecar = list(before = sc_before[c("live", "live_with_ast")],
                 after = sc_after[c("live", "live_with_ast")])
), file.path(OUT, "wt004_results.rds"))
write_parquet(SC_GATE, file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt004_results.rds + alpha_scores.parquet + charts 2종")
