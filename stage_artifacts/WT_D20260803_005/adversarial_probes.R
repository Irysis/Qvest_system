# =============================================================================
# adversarial_probes.R — WT-D20260803_005 (FQ-131) Self-Adversarial 실측 검증
#   자가 비평을 말로 반박하지 않고 재본다.
#   AP-1 창 길이 취약성: rob36 최상위 bin 0.788(PASS 기준 통과)은 era 산물인가?
#         → 그 132쌍을 전이별·era 일치 여부로 분해. era 일치 쌍을 빼면 남는가?
#   AP-2 top-80 절단 x 유동성 필터 상호작용: 유동성 편향 factor에서 절단이 무는가?
#         → 월별 top-80 중 유동성 통과 개수 census + 유동성-틸트 factor 3종 전체패널 parity
#   AP-3 defense family 0.465 는 위기 캘린더 종속인가?
#         → defense factor 창별 t 와 그 창의 BM<0 월 비중의 관계
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/adversarial_probes.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005AP] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
DBR <- readRDS(file.path(OUT, "dualbasis_results.rds"))
META<- readRDS(file.path(OUT, "pool_meta.rds"))
CP  <- readRDS(file.path(OUT, "canonical_pool.rds"))
POOL <- P1R$pool

# ── AP-1. rob36 최상위 bin 은 era 산물인가 ─────────────────────────────────
TT36 <- P1R$TG$rob36$t
era36 <- sign(apply(TT36, 1, mean, na.rm = TRUE))
P36 <- copy(P1R$PR$rob36)
P36[, era_k := era36[k]][, era_next := era36[k + 1L]]
P36[, era_aligned_k := sign(t_k) == era_k]
P36[, era_aligned_next := sign(t_next) == era_next]
TOP <- P36[abs(t_k) >= 2]
say("AP-1 rob36 최상위 bin: n=%d, 전체 지속 %.3f", nrow(TOP), TOP[, mean(sign(t_k)==sign(t_next))])
say("  전이별 분포:"); print(TOP[, .(n = .N, p = mean(sign(t_k)==sign(t_next)),
     era_k = unique(era_k), era_next = unique(era_next)), by = k][order(k)])
say("  era 부호가 창 k→k+1 로 유지된 전이의 쌍: %d / era 전환 전이의 쌍: %d",
    TOP[era_k == era_next, .N], TOP[era_k != era_next, .N])
sp <- TOP[, .(n = .N, p = mean(sign(t_k)==sign(t_next))), by = .(era_persists = era_k == era_next)]
print(sp)
ap1 <- list(n = nrow(TOP), p_all = TOP[, mean(sign(t_k)==sign(t_next))],
            by_era_persist = sp,
            share_from_era_persisting_transitions = TOP[era_k == era_next, .N] / nrow(TOP))
say("★ AP-1 판정: 최상위 bin 쌍의 %.0f%% 가 'era 부호가 유지된 전이'에서 나왔다. era 전환 전이에서의 지속 = %s",
    100 * ap1$share_from_era_persisting_transitions,
    ifelse(nrow(sp[era_persists == FALSE]), sprintf("%.3f (n=%d)",
      sp[era_persists == FALSE, p], sp[era_persists == FALSE, n]), "표본 0 — 판별 불가"))
# primary 격자에서도 동일 분해
TTp <- P1R$TG$primary$t; erap <- sign(apply(TTp, 1, mean, na.rm = TRUE))
Pp <- copy(P1R$PR$primary)[, `:=`(era_k = erap[k], era_next = erap[k + 1L])]
TOPp <- Pp[abs(t_k) >= 2]
print(TOPp[, .(n = .N, p = mean(sign(t_k)==sign(t_next))), by = .(era_persists = era_k == era_next)])

# ── AP-2. top-80 절단 x 유동성 필터 census ─────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, META$sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
PANEL <- as.data.table(read_parquet(file.path(OUT, "pool_panel.parquet")))
PANEL[, Date := as.Date(Date)]
PL <- merge(PANEL, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
PL[, pass_liq := is.na(adv) | adv >= 2e8]
CEN <- PL[, .(n_stored = .N, n_liq_pass = sum(pass_liq),
              rank_of_25th_pass = { r <- rank_in_factor[pass_liq]; if (length(r) >= 25L) sort(r)[25] else NA_integer_ }),
          by = .(Factor_Name, Date)]
say("AP-2 절단 census: factor-월 %d개 | 유동성 통과 <25 인 factor-월 %d (%.3f%%) | 25번째 통과분의 저장랭크 최대 %d",
    nrow(CEN), CEN[n_liq_pass < 25L, .N], 100*CEN[n_liq_pass < 25L, .N]/nrow(CEN),
    CEN[, max(rank_of_25th_pass, na.rm = TRUE)])
worst <- CEN[, .(min_pass = min(n_liq_pass), max_rank25 = max(rank_of_25th_pass, na.rm = TRUE),
                 n_short = sum(n_liq_pass < 25L)), by = Factor_Name][order(-max_rank25)]
print(head(worst, 10))
say("★ AP-2: 저장 top-80 안에서 25번째 유동종목이 항상 잡혔는가 = %s (최대 필요 랭크 %d <= 80)",
    ifelse(CEN[, max(rank_of_25th_pass, na.rm = TRUE)] <= 80L, "YES", "NO"),
    CEN[, max(rank_of_25th_pass, na.rm = TRUE)])

# 유동성-틸트 factor 3종 전체패널 parity 재확인
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)
p2_f <- intersect(c("L01_Amihud", "L06_Zero_Trade_Days", "S01_Size", "L26_Log_MktCap"), POOL)
say("AP-2b 유동성/사이즈 틸트 factor parity 대상: %s", paste(p2_f, collapse = ", "))
sink(file.path(OUT, "ap2_connector.log"))
FL <- rbindlist(Filter(Negate(is.null), lapply(META$sig_all, function(d) {
  tk <- UNIV[.(d), Ticker, nomatch = 0L]
  fd <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = p2_f), error = function(e) NULL)
  if (is.null(fd) || !nrow(fd)) return(NULL)
  fd[Ticker %in% tk & is.finite(Z_Score_Aligned), .(Date = d, Ticker, Factor_Name, score = Z_Score_Aligned)]
})))
sink()
setkey(PANEL, Factor_Name, Date, Ticker)
canon <- function(sc, tag) canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
  cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260803_005",
  strategy_id = paste0("WT_D20260803_005_", tag), diag_dual_basis = FALSE)
AP2B <- rbindlist(lapply(p2_f, function(f) {
  a <- canon(FL[Factor_Name == f, .(Date, Ticker, score)], paste0("AP2FULL_", f))
  b <- canon(PANEL[.(f), .(Date, Ticker, score), nomatch = 0L], paste0("AP2TOPK_", f))
  m <- merge(as.data.table(a$period_returns)[, .(date, x = ret_net)],
             as.data.table(b$period_returns)[, .(date, y = ret_net)], by = "date")
  data.table(Factor = f, n = nrow(m), max_abs_diff = max(abs(m$x - m$y)),
             t_full = a$portfolio_alpha_t_nw_lag3, t_topk = b$portfolio_alpha_t_nw_lag3)
}))
print(AP2B)
say("★ AP-2b: 유동성/사이즈 틸트 factor에서도 절단 무해 = %s (max diff %.1e)",
    ifelse(all(AP2B$max_abs_diff < 1e-12), "YES", "NO"), max(AP2B$max_abs_diff))

# ── AP-3. defense family 저지속성은 위기 캘린더 종속인가 ───────────────────
COND <- P1R$cond
defs <- COND[family == "defense", Factor_Name]
BM <- bench_dt[Date %in% as.Date(rownames(P1R$A))]
bnd <- P1R$TG$primary
badshare <- vapply(seq_along(bnd$from), function(k)
  BM[Date >= bnd$from[k] & Date <= bnd$to[k], mean(BM_Ret < 0)], numeric(1))
DEF <- data.table(k = seq_along(badshare), bad_share = badshare,
  mean_t_def = apply(P1R$TG$primary$t[, intersect(defs, colnames(P1R$TG$primary$t)), drop = FALSE], 1, mean, na.rm = TRUE),
  mean_t_all = apply(P1R$TG$primary$t, 1, mean, na.rm = TRUE))
DEF[, def_minus_all := mean_t_def - mean_t_all]
print(DEF)
say("★ AP-3: 창별 (defense 평균 t − 전체 평균 t) vs 그 창의 BM<0 월 비중 상관 = %.3f (n=%d 창)",
    suppressWarnings(cor(DEF$bad_share, DEF$def_minus_all)), nrow(DEF))

saveRDS(list(ap1 = ap1, ap1_primary = TOPp[, .(n = .N, p = mean(sign(t_k)==sign(t_next))),
             by = .(era_persists = era_k == era_next)],
             ap2_census = CEN[, .(factor_months = .N, short_months = sum(n_liq_pass < 25L),
                                  max_rank25 = max(rank_of_25th_pass, na.rm = TRUE))],
             ap2_worst = head(worst, 10), ap2b_parity = AP2B, ap3 = DEF,
             ap3_cor = suppressWarnings(cor(DEF$bad_share, DEF$def_minus_all)),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "adversarial_probes.rds"))
say("저장 — adversarial_probes.rds")
