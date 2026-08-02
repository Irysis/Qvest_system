# =============================================================================
# run_wt004_eval.R — WT-D20260802_004 단계 2/2: 조건부 평가 (AX-001 v2 3축)
#
#   (b) 5축 상관·직교성 실측 → C_ORTH 멤버십 (사전등록 규칙 — 성과 무참조)
#   (c) 단일 vs 조합: crisis_alpha / Core 대비 MDD / bad-normal IC ratio
#   (d) 전기간 지표 병기 (canonical_screen_bt 실측 — 승격 근거 아님)
#   (e) cap-tier 분해 (dual-basis: cap-w HARD + EW-uni + cap-tier)
#
#   국면 라벨 = 기존 unified_regime_signal.parquet Category (자체 정의 금지 준수).
#   라벨 용도 = **사후 조건부 귀속(evaluation slicing)에 한정** — 포트폴리오 구성에
#   국면 신호를 일절 사용하지 않음 (국면-조건부 신호 없음 → C5 overlay 타이밍
#   의무 비발동. 홀딩월 라벨은 홀딩월 실현 국면으로 귀속하는 attribution 표준).
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_004/run_wt004_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt004e] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns

F5   <- c("D03_RealVol", "D01_IdioVol", "D41_Vol_of_Vol", "D45_Downside_Dev", "D55_Vol_Trend")
CORE <- "M01_Mom_12_1"
PRIMACY <- F5  # 사전등록 일반->특수 우선순위 (컴파일 스크립트 헤더와 동일)
meta <- readRDS(file.path(OUT, "compile_meta.rds"))
SIG  <- meta$SIG

# -----------------------------------------------------------------------------
# 1. 패널 로드 (canonical) — defensive = -1 × canonical (parity 검증 완료)
# -----------------------------------------------------------------------------
pan <- list()
for (f in c(F5, CORE)) {
  d <- as.data.table(read_parquet(file.path(OUT, sprintf("panel_%s_canonical.parquet", f))))
  pan[[f]] <- d[is.finite(value)]
}
say("패널 로드: %s", paste(sprintf("%s=%d", names(pan), sapply(pan, nrow)), collapse=" "))

# -----------------------------------------------------------------------------
# 2. 시장 harness (forward returns / bench / liq / size)
# -----------------------------------------------------------------------------
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]           # SIG + 마지막 월말 (forward 종점)
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[Date %in% SIG, .(Date, Ticker, Size)]
say("returns %d행 · bench %d월 · liq %d행", nrow(returns_dt), nrow(bench_dt), nrow(liq_dt))

# 라벨 방향 감사 (동적 — Ret_1m이 실제 forward인지)
chk <- merge(pan[[CORE]][, .(Date, Ticker, score = value)], returns_dt, by = c("Date","Ticker"))
ic_chk <- chk[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date]
say("라벨 방향 감사(참고): M01 canonical rank-IC 평균 %.4f (모멘텀 양수 기대)", ic_chk[, mean(ic, na.rm=TRUE)])

# -----------------------------------------------------------------------------
# 3. (b) 5축 횡단면 상관 실측 → C_ORTH (성과 무참조 규칙)
# -----------------------------------------------------------------------------
wide <- Reduce(function(a, b) merge(a, b, by = c("Date","Ticker"), all = TRUE),
               lapply(F5, function(f) setnames(pan[[f]][, .(Date, Ticker, value)],
                                               "value", f)))
cor_by_month <- wide[, {
  M <- cor(as.matrix(.SD), use = "pairwise.complete.obs", method = "spearman")
  as.list(M[upper.tri(M)])
}, by = Date, .SDcols = F5]
pair_names <- outer(F5, F5, paste, sep = "~")[upper.tri(diag(5))]
setnames(cor_by_month, old = setdiff(names(cor_by_month), "Date"), new = pair_names)
cor_mean <- sapply(pair_names, function(p) mean(cor_by_month[[p]], na.rm = TRUE))
cor_sd   <- sapply(pair_names, function(p) sd(cor_by_month[[p]],  na.rm = TRUE))
say("--- 5축 월별 횡단면 Spearman (평균±sd) ---")
for (p in pair_names) say("  %s: %+.3f ± %.3f", p, cor_mean[p], cor_sd[p])

# C_ORTH: |rho_mean| >= 0.8 쌍은 PRIMACY 후순위 제거
drop <- character(0)
for (p in pair_names) {
  if (abs(cor_mean[p]) >= 0.8) {
    ab <- strsplit(p, "~", fixed = TRUE)[[1]]
    later <- ab[which.max(match(ab, PRIMACY))]
    drop <- union(drop, later)
  }
}
ORTH <- setdiff(F5, drop)
say("C_ORTH 멤버십(사전등록 규칙): {%s} (제거: %s)", paste(ORTH, collapse=", "),
    ifelse(length(drop), paste(drop, collapse=", "), "없음"))

# -----------------------------------------------------------------------------
# 4. 전략 패널 구축 — defensive lane(-z) 단일 5 + 조합 2 / canonical lane 동형 / Core
#    조합 = 등가중 합 (z_score_aligned_equal_weight; 합=평균×k, 순위 동치)
# -----------------------------------------------------------------------------
combo_panel <- function(members, sign_) {
  w <- wide[, c("Date","Ticker", members), with = FALSE]
  ok <- rowSums(!is.na(as.matrix(w[, members, with = FALSE]))) == length(members)
  w <- w[ok]
  w[, score := sign_ * rowSums(as.matrix(.SD)), .SDcols = members]
  w[, .(Date, Ticker, score)]
}
strategies <- list()
for (f in F5) {
  strategies[[paste0(f, "_def")]] <- pan[[f]][, .(Date, Ticker, score = -value)]
  strategies[[paste0(f, "_can")]] <- pan[[f]][, .(Date, Ticker, score =  value)]
}
strategies[["C_ALL5_def"]] <- combo_panel(F5, -1)
strategies[["C_ALL5_can"]] <- combo_panel(F5, +1)
strategies[["C_ORTH_def"]] <- combo_panel(ORTH, -1)
strategies[["C_ORTH_can"]] <- combo_panel(ORTH, +1)
strategies[["CORE_M01"]]   <- pan[[CORE]][, .(Date, Ticker, score = value)]

# ast_features: 컴파일 manifest에서 (단일 = defensive/canonical manifest, 조합 = eval 후 probe 컴파일)
read_feats <- function(p) tryCatch(fromJSON(file.path(OUT, p))$ast_features, error = function(e) NULL)
feats <- list()
for (f in F5) {
  feats[[paste0(f, "_def")]] <- read_feats(sprintf("ast_manifest_%s_defensive.json", f))
  feats[[paste0(f, "_can")]] <- read_feats(sprintf("ast_manifest_%s_canonical.json", f))
}
feats[["CORE_M01"]] <- read_feats(sprintf("ast_manifest_%s_canonical.json", CORE))

# 조합 AST 선언 + probe 컴파일 (manifest 취득 + parity)
source("02_Infrastructure/ast/ast_compile.R")
leaf_of <- function(f) list(type = "leaf", class = "FIELD", source = "factor_db_monthly", field = f)
const_neg1 <- list(type = "const", value = -1)
mk_combo_ast <- function(members, sign_) {
  nodes <- lapply(members, function(f)
    if (sign_ < 0) list(type = "op", op = "MUL", args = list(leaf_of(f), const_neg1)) else leaf_of(f))
  # ADD는 arity 2 가능성 — 이진 중첩으로 결합 (n-ary 미지원 대비)
  acc <- nodes[[1]]
  for (i in seq_along(nodes)[-1]) acc <- list(type = "op", op = "ADD", args = list(acc, nodes[[i]]))
  acc
}
# probe: 연속 4개월 협창 (컴파일러가 eval_dates min~max 스팬 전체 월그리드를 순회하는
#   실측 거동 때문 — 분산 날짜는 준-전체 컴파일 유발. parity는 대수 검증이라 협창 충분)
probe_dates <- SIG[format(SIG, "%Y-%m") %in% c("2020-01","2020-02","2020-03","2020-04")]
UNIV_probe <- unique(rbindlist(lapply(pan[F5], function(d) d[Date %in% probe_dates, .(Date, Ticker)])))
for (cn in c("C_ALL5", "C_ORTH")) {
  members <- if (cn == "C_ALL5") F5 else ORTH
  for (ln in c("def","can")) {
    tag <- paste0(cn, "_", ln)
    fp  <- file.path(OUT, sprintf("ast_%s.json", tag))
    write_json(mk_combo_ast(members, ifelse(ln == "def", -1, +1)), fp, auto_unbox = TRUE, pretty = TRUE)
    cmp <- tryCatch(ast_compile(fp, eval_dates = probe_dates, universe = UNIV_probe,
                    manifest_out = file.path(OUT, sprintf("ast_manifest_%s.json", tag))),
                    error = function(e) { say("combo compile ERR %s: %s", tag, conditionMessage(e)); NULL })
    if (!is.null(cmp)) {
      m <- merge(cmp$panel[, .(Date, Ticker, v_ast = value)],
                 strategies[[tag]][, .(Date, Ticker, v_drv = score)], by = c("Date","Ticker"))
      m <- m[is.finite(v_ast) & is.finite(v_drv)]
      mad_ <- if (nrow(m)) m[, max(abs(v_ast - v_drv))] else NA_real_
      say("combo parity %s: n=%d max|diff|=%.2e %s", tag, nrow(m), mad_,
          ifelse(is.finite(mad_) && mad_ < 1e-10, "PASS", "CHECK"))
      feats[[tag]] <- cmp$manifest$ast_features
    }
  }
}

# -----------------------------------------------------------------------------
# 5. canonical_screen_bt 실측 (top25 EW, 15bps, liq 2e8, dual-basis, ast_features)
# -----------------------------------------------------------------------------
bt <- list()
for (tag in names(strategies)) {
  sc <- strategies[[tag]][is.finite(score), .(Date, Ticker, score)]
  r <- canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_004", strategy_id = paste0("WT_D20260802_004_VOLC_", tag),
        diag_dual_basis = TRUE, size_dt = size_dt,
        ast_features = feats[[tag]])
  bt[[tag]] <- r
  ew <- r$diag_ew_universe
  say("%-14s PORT_t=%+.2f netSR=%+.3f IR=%+.3f TO=%.0f%% n=%d | EW-uni t=%s",
      tag, r$portfolio_alpha_t_nw_lag3, r$net_sr %||% NA, r$information_ratio %||% NA,
      100*(r$turnover_annual %||% NA), r$n_months,
      format(ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, digits = 3))
}

# -----------------------------------------------------------------------------
# 6. AX-001 v2 조건부 3축
# -----------------------------------------------------------------------------
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym,1,4)); m <- as.integer(substr(ym,6,7)) + k
  y <- y + (m-1L) %/% 12L; m <- (m-1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(list(mean = mean(x), t = NA_real_, n = length(x)))
  fit <- lm(x ~ 1)
  tv <- tryCatch(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3],
                 error = function(e) NA_real_)
  list(mean = mean(x), t = as.numeric(tv), n = length(x))
}
episode_of <- function(yms) {  # 연속 월 → 에피소드 id
  d <- as.integer(substr(yms,1,4)) * 12L + as.integer(substr(yms,6,7))
  cumsum(c(1L, diff(d) != 1L))
}
cond_eval <- function(r) {
  pr <- as.data.table(r$period_returns)
  pr[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
  pr <- merge(pr, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
  pr[, active := ret_net - benchmark_ret]
  crisis <- pr[Category == "CRISIS"][order(hold_ym)]
  bad    <- pr[benchmark_ret < 0]
  normal <- pr[benchmark_ret >= 0]
  ep <- NULL
  if (nrow(crisis)) {
    crisis[, ep := episode_of(hold_ym)]
    ep <- crisis[, .(months = .N, first = min(hold_ym), last = max(hold_ym),
                     cum_active = sum(active), cum_net = sum(ret_net), cum_bm = sum(benchmark_ret)), by = ep]
  }
  mdd <- tryCatch({
    x <- xts(pr$ret_net, order.by = as.Date(paste0(pr$hold_ym, "-01")))
    as.numeric(PerformanceAnalytics::maxDrawdown(x))
  }, error = function(e) NA_real_)
  ca <- nw_t(crisis$active)
  list(
    crisis_alpha_mean_monthly = ca$mean, crisis_alpha_t_nw = ca$t, crisis_n_months = ca$n,
    crisis_episodes = ep,
    crisis_alpha_event_count = if (!is.null(ep)) sum(ep$cum_active > 0) else 0L,
    n_episodes = if (!is.null(ep)) nrow(ep) else 0L,
    bad_mean_active = mean(bad$active), normal_mean_active = mean(normal$active),
    mdd_full = mdd,
    pr = pr
  )
}
cond <- lapply(bt, cond_eval)

core_mdd <- cond[["CORE_M01"]]$mdd_full
bm_x <- xts(cond[["CORE_M01"]]$pr$benchmark_ret,
            order.by = as.Date(paste0(cond[["CORE_M01"]]$pr$hold_ym, "-01")))
bm_mdd <- as.numeric(PerformanceAnalytics::maxDrawdown(bm_x))
say("--- AX-001 조건부 3축 (crisis=%d월/%d에피소드, Core=M01 top25 MDD=%.1f%%, BM MDD=%.1f%%) ---",
    cond[[1]]$crisis_n_months, cond[[1]]$n_episodes, 100*core_mdd, 100*bm_mdd)
for (tag in names(cond)) {
  cc <- cond[[tag]]
  say("%-14s crisisA=%+.2f%%/월 (t=%+.2f) 이벤트 %d/%d + | MDD %.1f%% (Core대비 %+.1fpp)",
      tag, 100*cc$crisis_alpha_mean_monthly, cc$crisis_alpha_t_nw %||% NA,
      cc$crisis_alpha_event_count, cc$n_episodes, 100*cc$mdd_full,
      100*(core_mdd - cc$mdd_full))
}

# -----------------------------------------------------------------------------
# 7. bad/normal IC ratio (팩터·조합 defensive 배향) + advisory 진단
# -----------------------------------------------------------------------------
ic_eval <- function(sc) {
  d <- merge(sc[is.finite(score)], returns_dt, by = c("Date","Ticker"))
  ics <- d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date]
  ics <- merge(ics, bench_dt, by = "Date")           # BM_Ret = 같은 홀딩구간 forward
  ics[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
  ics <- merge(ics, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
  bad_ic  <- ics[BM_Ret < 0,  mean(ic, na.rm = TRUE)]
  norm_ic <- ics[BM_Ret >= 0, mean(ic, na.rm = TRUE)]
  reg_bad <- ics[Category %in% c("CRISIS","CAUTION"), mean(ic, na.rm = TRUE)]
  reg_nrm <- ics[!Category %in% c("CRISIS","CAUTION"), mean(ic, na.rm = TRUE)]
  n <- ics[, sum(is.finite(ic))]
  list(mean_ic = ics[, mean(ic, na.rm = TRUE)],
       icir = ics[, mean(ic, na.rm=TRUE)/sd(ic, na.rm=TRUE)],
       ic_t = ics[, mean(ic, na.rm=TRUE)/sd(ic, na.rm=TRUE)*sqrt(sum(is.finite(ic)))],
       n_months = n,
       bad_ic = bad_ic, normal_ic = norm_ic,
       bad_normal_ratio = bad_ic / norm_ic,
       regime_bad_ic = reg_bad, regime_normal_ic = reg_nrm,
       regime_ratio = reg_bad / reg_nrm,
       ic_series = ics[, .(Date, hold_ym, ic, BM_Ret, Category)])
}
ic_res <- list()
for (tag in c(paste0(F5, "_def"), "C_ALL5_def", "C_ORTH_def")) {
  ic_res[[tag]] <- ic_eval(strategies[[tag]])
  r <- ic_res[[tag]]
  say("%-16s IC=%+.4f ICIR=%+.3f | bad_IC=%+.4f normal_IC=%+.4f ratio=%s | regime-ratio=%s",
      tag, r$mean_ic, r$icir, r$bad_ic, r$normal_ic,
      format(r$bad_normal_ratio, digits=3), format(r$regime_ratio, digits=3))
}

# -----------------------------------------------------------------------------
# 8. 저장
# -----------------------------------------------------------------------------
slim_bt <- lapply(bt, function(r) r[setdiff(names(r), "benchmark_compare")])
saveRDS(list(bt = slim_bt, cond = lapply(cond, function(x) x[setdiff(names(x), "pr")]),
             pr = lapply(cond, `[[`, "pr"),
             ic = ic_res, cor_mean = cor_mean, cor_sd = cor_sd, ORTH = ORTH,
             core_mdd = core_mdd, bm_mdd = bm_mdd),
        file.path(OUT, "wt004_eval_results.rds"))
write_parquet(strategies[["C_ORTH_def"]], file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt004_eval_results.rds + alpha_scores.parquet")
