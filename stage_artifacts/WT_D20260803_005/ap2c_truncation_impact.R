# =============================================================================
# ap2c_truncation_impact.R — WT-D20260803_005 자기적대검증 AP-2 후속
#   AP-2b가 L26_Log_MktCap 에서 top-80 절단 불일치(max|Δret| 2.1e-2, PORT_t 0.7618→0.7438)를
#   냈다. 최초 P1 parity(3 주류 factor, 정확 0)는 이 사각을 못 봤다 — "검사가 옳은 것을
#   재지만 잘못된 표본에 서 있었다".
#   본 probe: 절단이 무는 factor 전수 식별 → 전체 패널로 재측정 → **창 부호가 바뀌는가**를
#   판정한다(본 라운드 판정 단위 = 부호).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/ap2c_truncation_impact.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005AP2c] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
nw_t <- function(x, lag = 3L) .nw_t_mean(x, lag = lag)

P1R <- readRDS(file.path(OUT, "persistence_results.rds")); META <- readRDS(file.path(OUT, "pool_meta.rds"))
POOL <- P1R$pool; GRIDS <- P1R$grids
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, META$sig_all)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench_dt <- fwd$bench_dt[, .(Date=as.Date(Date), BM_Ret)]
liq_dt <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)
PANEL <- as.data.table(read_parquet(file.path(OUT,"pool_panel.parquet"))); PANEL[, Date := as.Date(Date)]
setkey(PANEL, Factor_Name, Date, Ticker)

# ── 절단이 물 수 있는 factor 전수 식별 (보수적: rank25 >= 70 또는 short month 존재) ──
PANEL <- PANEL[Factor_Name %in% POOL]        # 중복 제거 후 풀만 (A 행렬 열과 정합)
PL <- merge(PANEL, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
PL[, pass := is.na(adv) | adv >= 2e8]
CEN <- PL[, .(n_pass = sum(pass),
              rank25 = { r <- rank_in_factor[pass]; if (length(r) >= 25L) sort(r)[25] else NA_integer_ }),
          by = .(Factor_Name, Date)]
SUS <- CEN[, .(max_rank25 = max(rank25, na.rm = TRUE), n_short = sum(n_pass < 25L),
               n_tight = sum(rank25 >= 70L, na.rm = TRUE)), by = Factor_Name][
             max_rank25 >= 70 | n_short > 0][order(-max_rank25, -n_short)]
say("절단 위험 factor: %d / %d (rank25>=70 또는 short month 존재)", nrow(SUS), length(POOL))
print(head(SUS, 20))
TARGET <- SUS$Factor_Name
if (!length(TARGET)) { say("대상 0 — 종료"); quit(save = "no") }

# ── 전체 패널 재구축 (대상 factor만) → 창 부호 비교 ────────────────────────
sink(file.path(OUT, "ap2c_connector.log"))
FULL <- rbindlist(Filter(Negate(is.null), lapply(META$sig_all, function(d) {
  tk <- UNIV[.(d), Ticker, nomatch = 0L]
  fd <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = TARGET),
                 error = function(e) NULL)
  if (is.null(fd) || !nrow(fd)) return(NULL)
  fd[Ticker %in% tk & is.finite(Z_Score_Aligned), .(Date=d, Ticker, Factor_Name, score=Z_Score_Aligned)]
})))
sink()
canon <- function(sc, tag) canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
  cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260803_005",
  strategy_id = paste0("WT_D20260803_005_", tag), diag_dual_basis = FALSE)
DATES <- as.Date(rownames(P1R$A))
make_bounds <- function(n, W) { b <- list(); e <- n
  while (e-W+1L >= 1L) { b[[length(b)+1L]] <- c(e-W+1L, e); e <- e-W }; rev(b) }
win_t <- function(v, bnd, mo) vapply(bnd, function(ix) { x <- v[ix[1]:ix[2]]; xv <- x[is.finite(x)]
  if (length(xv) < mo || length(xv)/(ix[2]-ix[1]+1L) < 0.90) return(NA_real_); nw_t(xv) }, numeric(1))

CMP <- rbindlist(lapply(TARGET, function(f) {
  a <- canon(FULL[Factor_Name == f, .(Date, Ticker, score)], paste0("AP2C_FULL_", f))
  pr <- as.data.table(a$period_returns)
  vfull <- rep(NA_real_, length(DATES)); names(vfull) <- as.character(DATES)
  vfull[as.character(pr$date)] <- pr$ret_net - pr$benchmark_ret
  vtopk <- P1R$A[, f]
  rbindlist(lapply(names(GRIDS), function(nm) {
    g <- GRIDS[[nm]]; bnd <- make_bounds(length(DATES), g$W)
    tf <- win_t(vfull, bnd, g$min_obs); tk <- win_t(vtopk, bnd, g$min_obs)
    data.table(Factor_Name = f, grid = nm, window = seq_along(bnd),
               t_topk = tk, t_full = tf, dt = tf - tk,
               sign_same = sign(tf) == sign(tk))
  }))
}))
CMP <- CMP[is.finite(t_topk) & is.finite(t_full)]
say("비교 셀 %d개 | |Δt| 중앙 %.4f / 최대 %.4f | 부호 불일치 %d (%.2f%%)",
    nrow(CMP), median(abs(CMP$dt)), max(abs(CMP$dt)), sum(!CMP$sign_same),
    100*mean(!CMP$sign_same))
if (any(!CMP$sign_same)) print(CMP[sign_same == FALSE][order(-abs(dt))])

# 판정 영향: 부호 불일치 셀을 전체 패널 값으로 교체했을 때 primary P_persist 변화
Ap <- P1R$A
for (f in TARGET) {
  a <- NULL
}
TTp <- P1R$TG$primary$t
TTp2 <- TTp
for (i in seq_len(nrow(CMP[grid == "primary"]))) {
  r <- CMP[grid == "primary"][i]
  TTp2[r$window, r$Factor_Name] <- r$t_full
}
pairs_of <- function(TT) rbindlist(lapply(seq_len(nrow(TT)-1L), function(k) {
  tk <- TT[k,]; tn <- TT[k+1L,]; ok <- is.finite(tk) & is.finite(tn)
  if (!any(ok)) return(NULL)
  data.table(Factor_Name = colnames(TT)[ok], k = k, t_k = tk[ok], t_next = tn[ok]) }))
p_old <- { P <- pairs_of(TTp); mean(sign(P$t_k) == sign(P$t_next)) }
p_new <- { P <- pairs_of(TTp2); mean(sign(P$t_k) == sign(P$t_next)) }
bin_old <- { P <- pairs_of(TTp)[abs(t_k) >= 2]; mean(sign(P$t_k) == sign(P$t_next)) }
bin_new <- { P <- pairs_of(TTp2)[abs(t_k) >= 2]; mean(sign(P$t_k) == sign(P$t_next)) }
say("★ 판정 영향(primary): P_persist %.4f → %.4f (Δ %+.4f) | 최상위 bin %.4f → %.4f (Δ %+.4f)",
    p_old, p_new, p_new - p_old, bin_old, bin_new, bin_new - bin_old)
say("★ 결론: 절단 편향이 본 라운드 판정을 바꾸는가 = %s",
    ifelse(abs(p_new - p_old) < 0.01 && abs(bin_new - bin_old) < 0.03, "NO(영향 정량 확인)", "YES — 재측정 필요"))

saveRDS(list(suspects = SUS, cmp = CMP, p_old = p_old, p_new = p_new,
             bin_old = bin_old, bin_new = bin_new, n_target = length(TARGET),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "ap2c_truncation.rds"))
say("저장 — ap2c_truncation.rds")
