# =============================================================================
# adversarial_probes.R — WT-D20260803_007 (FQ-135) Self-Adversarial Challenge (v8.2)
#   finalize 직전 자기 적대검증. 각 probe 는 "내 결론을 무너뜨릴 수 있는 경로"를 실측한다.
#
#   AP1 era 창 길이(W=36) 임의성 — W∈{24,48} 에서 판별식 (a)/(b) 재측정
#   AP2 A_PERP_TOP 퇴화 혐의 — level 제거 후 지표가 '죽은 factor 선택기'로 변질했나
#   AP3 lag1 붕괴가 하네스 미래참조인가 신호 감쇠인가 — POOL_EW 통제 + rank IC lag0/lag1
#   AP4 판별 문턱 취약성 — paired t 의 블록 부트스트랩 CI (단일 draw 아닌가)
#   AP5 벤치 basis 교락 — paired 판별식이 cap-w 아티팩트에 오염됐나 (수학적 상쇄 실증)
# 실행: Rscript stage_artifacts/WT_D20260803_007/adversarial_probes.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007X] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
nwt <- function(x, lag = 3L, min_obs = 20L) { xv <- x[is.finite(x)]
  if (length(xv) < min_obs) return(NA_real_); .nw_t_mean(xv, lag = lag) }

MB  <- readRDS(file.path(OUT, "memberships.rds"))
AR  <- readRDS(file.path(OUT, "arm_results.rds"))
PH  <- readRDS(file.path(OUT, "posthoc_results.rds"))
PR5 <- readRDS(file.path(SRC5, "persistence_results.rds"))
CP5 <- readRDS(file.path(SRC5, "canonical_pool.rds"))
LAB <- readRDS(file.path(SRC5, "registry_labels.rds"))
A <- PR5$A; POOL <- MB$pool; DATES <- MB$dates; steps <- MB$steps; NM <- nrow(A)
K <- MB$consts$K_PRIM; CM <- MB$consts$COV_MIN_MEMBER
pick <- function(v, K, top = TRUE) { v <- v[is.finite(v)]
  names(v)[order(v, names(v), decreasing = top)[seq_len(min(K, length(v)))]] }
PRB <- AR$res_period_returns
pa <- function(nm) as.data.table(PRB[[nm]])[, .(date, active = ret_net - benchmark_ret)]

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)
META <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
canon <- function(sc, tag) canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
  cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260803_007",
  strategy_id = paste0("WT_D20260803_007_X_", tag), diag_dual_basis = FALSE)

# ── AP1 : era 창 길이 임의성 ────────────────────────────────────────────────
era_metric <- function(is_end, W, era_min) {
  ne <- is_end %/% W; if (ne < 2L) return(NULL)
  bnds <- lapply(seq_len(ne), function(k) c(is_end - k*W + 1L, is_end - (k-1L)*W))
  TT <- do.call(rbind, lapply(bnds, function(b)
    apply(A[b[1]:b[2], , drop = FALSE], 2, nwt, min_obs = era_min)))
  TTrel <- TT - rowMeans(TT, na.rm = TRUE)
  apply(TTrel, 2, function(v) if (all(is.na(v))) NA_real_ else min(v, na.rm = TRUE))
}
WSET <- list(W24 = list(W = 24L, m = 20L), W48 = list(W = 48L, m = 40L))
memb_W <- list()
for (nm in names(WSET)) {
  g <- WSET[[nm]]
  memb_W[[paste0(nm, "_TOP")]] <- lapply(steps, function(st) pick(era_metric(st$is_end, g$W, g$m), K, TRUE))
  memb_W[[paste0(nm, "_BOT")]] <- lapply(steps, function(st) pick(era_metric(st$is_end, g$W, g$m), K, FALSE))
}
step_of <- rep(NA_integer_, NM); for (i in seq_along(steps)) step_of[steps[[i]]$oos] <- i
source("02_Infrastructure/factor_db/factor_db_connector.R")
sink(file.path(OUT, "probe_connector.log"))
acc <- vector("list", NM)
for (i in seq_len(NM)) {
  if (is.na(step_of[i])) next
  d <- DATES[i]; tk <- UNIV[.(d), Ticker, nomatch = 0L]; if (!length(tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  S <- fdt[Ticker %in% tk & Factor_Name %in% POOL & is.finite(Z_Score_Aligned),
           .(Ticker, Factor_Name, z = Z_Score_Aligned)]; rm(fdt)
  if (!nrow(S)) next
  lst <- lapply(names(memb_W), function(a) {
    mem <- memb_W[[a]][[step_of[i]]]
    Q <- S[Factor_Name %in% mem]; if (!nrow(Q)) return(NULL)
    nmf <- uniqueN(Q$Factor_Name)
    g <- Q[, .(cnt = .N, s = sum(z)), by = Ticker][cnt >= ceiling(CM * nmf)]
    if (!nrow(g)) return(NULL)
    data.table(arm = a, Date = d, Ticker = g$Ticker, score = g$s / g$cnt) })
  acc[[i]] <- rbindlist(Filter(Negate(is.null), lst))
  if (i %% 24L == 0L) gc(FALSE)
}
sink()
WP <- rbindlist(Filter(Negate(is.null), acc))
sink(file.path(OUT, "probe_canon.log"))
WRES <- lapply(sort(unique(WP$arm)), function(a) canon(WP[arm == a, .(Date, Ticker, score)], a))
names(WRES) <- sort(unique(WP$arm))
sink()
pw <- function(a) as.data.table(WRES[[a]]$period_returns)[, .(date, active = ret_net - benchmark_ret)]
cmp <- function(x, y, lbl) { m <- merge(x[, .(date, ax = active)], y[, .(date, ay = active)], by = "date")
  d <- m$ax - m$ay; data.table(pair = lbl, n = nrow(m), t_nw_lag3 = nwt(d), mean_diff_ann = 12*mean(d)) }
AP1 <- rbindlist(list(
  data.table(pair = "[기준] A_REL_TOP - A_REL_BOT (W=36)", n = 167L,
             t_nw_lag3 = AR$disc$a_t, mean_diff_ann = AR$pairs[pair=="A_REL_TOP - A_REL_BOT", mean_diff_ann]),
  data.table(pair = "[기준] A_REL_TOP - SINGLE_BEST (W=36)", n = 167L,
             t_nw_lag3 = AR$disc$b_t, mean_diff_ann = AR$pairs[pair=="A_REL_TOP - SINGLE_BEST", mean_diff_ann]),
  cmp(pw("W24_TOP"), pw("W24_BOT"), "W24_TOP - W24_BOT  [(a) 재측정]"),
  cmp(pw("W24_TOP"), pa("SINGLE_BEST"), "W24_TOP - SINGLE_BEST  [(b) 재측정]"),
  cmp(pw("W48_TOP"), pw("W48_BOT"), "W48_TOP - W48_BOT  [(a) 재측정]"),
  cmp(pw("W48_TOP"), pa("SINGLE_BEST"), "W48_TOP - SINGLE_BEST  [(b) 재측정]"),
  cmp(pw("W24_TOP"), PH$period_returns, "W24_TOP - LEVEL_TOP_K20 [robustness 순증분]"),
  cmp(pw("W48_TOP"), PH$period_returns, "W48_TOP - LEVEL_TOP_K20 [robustness 순증분]")))
AP1[, standalone_port_t := c(AR$summary[arm=="A_REL_TOP", port_t], AR$summary[arm=="A_REL_TOP", port_t],
  WRES$W24_TOP$portfolio_alpha_t_nw_lag3, WRES$W24_TOP$portfolio_alpha_t_nw_lag3,
  WRES$W48_TOP$portfolio_alpha_t_nw_lag3, WRES$W48_TOP$portfolio_alpha_t_nw_lag3,
  WRES$W24_TOP$portfolio_alpha_t_nw_lag3, WRES$W48_TOP$portfolio_alpha_t_nw_lag3)]
say("=== AP1 era 창 길이 임의성 ==="); print(AP1)
say("AP1 판정: W∈{24,36,48} 전부에서 (a) max %.3f / (b) max %.3f — 문턱 2.0 %s",
    max(AP1[grepl("\\(a\\)|A_REL_BOT", pair), t_nw_lag3], na.rm=TRUE),
    max(AP1[grepl("SINGLE_BEST", pair), t_nw_lag3], na.rm=TRUE),
    ifelse(max(AP1$t_nw_lag3, na.rm=TRUE) >= 2, "★일부 도달 — 재검토", "미달 (결론 강건)"))

# ── AP2 : A_PERP_TOP 퇴화 혐의 ──────────────────────────────────────────────
MET <- MB$met
SUMM5 <- CP5$summary
deg <- rbindlist(lapply(seq_along(MET), function(i) {
  m <- MET[[i]]; TT <- m$era_t
  esd <- apply(TT, 2, sd, na.rm = TRUE); mabs <- apply(abs(TT), 2, mean, na.rm = TRUE)
  data.table(step = i,
    cor_perp_erasd = cor(m$perp, esd, use = "pairwise.complete.obs"),
    cor_perp_meanabst = cor(m$perp, mabs, use = "pairwise.complete.obs"),
    cor_rel_erasd = cor(m$rel, esd, use = "pairwise.complete.obs"),
    cor_rel_meanabst = cor(m$rel, mabs, use = "pairwise.complete.obs")) }))
say("=== AP2 지표 퇴화 진단 (level 제거가 '죽은 factor 선택기'를 만드는가) ===")
print(deg)
mabs_all <- vapply(MET, function(m) mean(apply(abs(m$era_t), 2, mean, na.rm=TRUE)[
  pick(m$perp, K, TRUE)], na.rm=TRUE), 1.0)
mabs_rel <- vapply(MET, function(m) mean(apply(abs(m$era_t), 2, mean, na.rm=TRUE)[
  pick(m$rel, K, TRUE)], na.rm=TRUE), 1.0)
mabs_pool <- vapply(MET, function(m) mean(apply(abs(m$era_t), 2, mean, na.rm=TRUE), na.rm=TRUE), 1.0)
say("선택 멤버의 평균 |era t|: A_PERP_TOP %.3f / A_REL_TOP %.3f / 풀 전체 %.3f",
    mean(mabs_all), mean(mabs_rel), mean(mabs_pool))
famp <- data.table(Factor_Name = unlist(lapply(MET, function(m) pick(m$perp, K, TRUE))))
famp <- merge(famp, LAB[, .(Factor_Name, family)], by = "Factor_Name", all.x = TRUE)
say("A_PERP_TOP family 상위: %s", paste(sprintf("%s %.2f", names(sort(prop.table(table(famp$family)), decreasing=TRUE))[1:4],
    sort(prop.table(table(famp$family)), decreasing=TRUE)[1:4]), collapse = " / "))

# ── AP3 : lag1 붕괴 귀속 ────────────────────────────────────────────────────
MAINP <- as.data.table(read_parquet(file.path(OUT, "composite_main.parquet"))); MAINP[, Date := as.Date(Date)]
ic_of <- function(a, lagm = 0L) {
  P <- MAINP[arm == a, .(Date, Ticker, score)]
  if (lagm > 0L) { dts <- sort(unique(P$Date))
    P <- merge(P, data.table(Date = dts[-length(dts)], Dn = dts[-1]), by = "Date")[, .(Date = Dn, Ticker, score)] }
  M <- merge(P, returns_dt, by = c("Date","Ticker"))
  M[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date][is.finite(ic)]
}
AP3 <- rbindlist(lapply(c("A_REL_TOP","POOL_EW","A_REL_BOT","A_PERP_TOP"), function(a) {
  i0 <- ic_of(a, 0L); i1 <- ic_of(a, 1L)
  data.table(arm = a, ic_lag0 = mean(i0$ic), t_ic_lag0 = nwt(i0$ic),
             ic_lag1 = mean(i1$ic), t_ic_lag1 = nwt(i1$ic),
             ic_retention = mean(i1$ic) / mean(i0$ic)) }))
say("=== AP3 lag1 귀속: rank IC lag0 vs lag1 (하네스 미래참조면 POOL_EW 도 붕괴해야) ===")
print(AP3)
say("AP3 판정: POOL_EW IC 보존율 %.3f (하네스 수준 누출이면 ~0 이어야) | A_REL_TOP %.3f",
    AP3[arm=="POOL_EW", ic_retention], AP3[arm=="A_REL_TOP", ic_retention])

# ── AP4 : 판별 문턱 취약성 (블록 부트스트랩) ────────────────────────────────
blk_boot_t <- function(d, B = 2000L, block = 12L, seed = 20260803L) {
  set.seed(seed); n <- length(d); nb <- ceiling(n / block)
  vapply(seq_len(B), function(b) {
    st <- sample.int(n, nb, replace = TRUE)
    idx <- unlist(lapply(st, function(s) ((s - 1L) + seq_len(block) - 1L) %% n + 1L))[seq_len(n)]
    nwt(d[idx]) }, numeric(1)) }
dab <- { m <- merge(pa("A_REL_TOP")[, .(date, ax=active)], pa("A_REL_BOT")[, .(date, ay=active)], by="date"); m$ax - m$ay }
dbb <- { m <- merge(pa("A_REL_TOP")[, .(date, ax=active)], pa("SINGLE_BEST")[, .(date, ay=active)], by="date"); m$ax - m$ay }
dpp <- { m <- merge(pa("A_REL_TOP")[, .(date, ax=active)], PH$period_returns[, .(date, ay=active)], by="date"); m$ax - m$ay }
BA <- blk_boot_t(dab); BB <- blk_boot_t(dbb); BP <- blk_boot_t(dpp)
AP4 <- data.table(
  discriminant = c("(a) TOP-BOT", "(b) TOP-SINGLE_BEST", "[사후] TOP-LEVEL_TOP_K20"),
  t_point = c(AR$disc$a_t, AR$disc$b_t, PH$pairs[pair=="A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3]),
  boot_median = c(median(BA,na.rm=TRUE), median(BB,na.rm=TRUE), median(BP,na.rm=TRUE)),
  boot_q05 = c(quantile(BA,.05,na.rm=TRUE), quantile(BB,.05,na.rm=TRUE), quantile(BP,.05,na.rm=TRUE)),
  boot_q95 = c(quantile(BA,.95,na.rm=TRUE), quantile(BB,.95,na.rm=TRUE), quantile(BP,.95,na.rm=TRUE)),
  p_reach_2 = c(mean(BA >= 2, na.rm=TRUE), mean(BB >= 2, na.rm=TRUE), mean(BP >= 2, na.rm=TRUE)))
say("=== AP4 판별 문턱 취약성 (stationary block bootstrap, block=12, B=2000) ==="); print(AP4)

# ── AP5 : basis 교락 (paired 판별식의 벤치 상쇄 실증) ───────────────────────
x <- as.data.table(PRB[["A_REL_TOP"]]); y <- as.data.table(PRB[["A_REL_BOT"]])
m <- merge(x[, .(date, rx = ret_net, bx = benchmark_ret)], y[, .(date, ry = ret_net, by_ = benchmark_ret)], by = "date")
AP5 <- data.table(
  check = c("두 arm 의 벤치 시계열 동일", "active 차 == net 수익 차 (벤치 상쇄)"),
  value = c(max(abs(m$bx - m$by_)), max(abs((m$rx - m$bx) - (m$ry - m$by_) - (m$rx - m$ry)))))
say("=== AP5 basis 교락: paired 판별식은 벤치 선택에 불변인가 ==="); print(AP5)
say("AP5 판정: %s — cap-w 아티팩트(무작위 귀무 평균 %.3f)는 paired 차에서 정확히 상쇄. 단 standalone PORT_t 해석에는 여전히 구속.",
    ifelse(max(AP5$value) < 1e-12, "불변 확인", "★불변 아님 — 재검토"), mean(AR$rand$port_t, na.rm=TRUE))

saveRDS(list(ap1 = AP1, ap1_res = lapply(WRES, function(r) list(port_t = r$portfolio_alpha_t_nw_lag3,
  ir = r$information_ratio, turnover = r$turnover_annual)), ap2 = deg,
  ap2_mabs = list(perp = mean(mabs_all), rel = mean(mabs_rel), pool = mean(mabs_pool)),
  ap3 = AP3, ap4 = AP4, ap5 = AP5,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), file.path(OUT, "adversarial_probes.rds"))
say("저장 — adversarial_probes.rds")
