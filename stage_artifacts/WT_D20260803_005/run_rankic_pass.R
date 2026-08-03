# =============================================================================
# run_rankic_pass.R — WT-D20260803_005 (FQ-131) Step F
#   목적 둘:
#   (1) diagnostics.rank_ic (advisory, schema 필수 number) 를 **날조 없이** 실측한다.
#       top-80 절단 패널로는 단면 rank IC 를 편향 없이 못 구하므로 월별 전체 단면을
#       load_month_factors(C15) 로 한 번 더 순회해 factor x 월 Spearman 을 산출.
#   (2) ★ 전이 벽의 지속성 판: rank-IC 부호는 PORT_t 부호보다 오래 가는가?
#       - 오래 간다  → 신호는 안정, 불안정한 것은 top-25 long-only x cap-w 로의 *번역*
#       - 같이 불안정 → 신호 자체가 불안정
#       이 갈림은 "다음에 무엇을 고칠 것인가"를 정한다.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/run_rankic_pass.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005F] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
nw_t <- function(x, lag = 3L) .nw_t_mean(x, lag = lag)

META <- readRDS(file.path(OUT, "pool_meta.rds"))
P1R  <- readRDS(file.path(OUT, "persistence_results.rds"))
POOL <- P1R$pool; GRIDS <- P1R$grids
sig_all <- META$sig_all

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, sig_all)
RET <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
setkey(RET, Date, Ticker)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)

t0 <- Sys.time(); ic_list <- vector("list", length(sig_all))
sink(file.path(OUT, "rankic_connector.log"))
for (i in seq_along(sig_all)) {
  d <- sig_all[i]
  r <- RET[.(d), .(Ticker, Ret_1m), nomatch = 0L]
  if (nrow(r) < 50L) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = POOL),
                  error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  tk <- UNIV[.(d), Ticker, nomatch = 0L]
  M <- merge(fdt[Ticker %in% tk & is.finite(Z_Score_Aligned)], r, by = "Ticker")
  rm(fdt)
  if (!nrow(M)) next
  ic_list[[i]] <- M[, .(Date = d, n = .N,
      ic = if (.N >= 50L) suppressWarnings(cor(Z_Score_Aligned, Ret_1m, method = "spearman"))
           else NA_real_), by = Factor_Name]
  if (i %% 48L == 0L) { gc(FALSE); cat(sprintf("[ic] %d/%d\n", i, length(sig_all))) }
}
sink()
IC <- rbindlist(Filter(Negate(is.null), ic_list), use.names = TRUE)[is.finite(ic)]
say("rank IC 패널: %d행 / %d factor / %d월 (%.0fs)", nrow(IC), uniqueN(IC$Factor_Name),
    uniqueN(IC$Date), as.numeric(difftime(Sys.time(), t0, units = "secs")))

ICS <- IC[, .(mean_ic = mean(ic), sd_ic = sd(ic), n = .N,
              icir = mean(ic)/sd(ic), ic_t = mean(ic)/sd(ic)*sqrt(.N)), by = Factor_Name]
say("pool rank IC: 중앙값 %.4f (평균 %.4f) | ICIR 중앙값 %.3f | |mean_ic|>=0.02 factor %d/%d",
    median(ICS$mean_ic), mean(ICS$mean_ic), median(ICS$icir),
    ICS[abs(mean_ic) >= 0.02, .N], nrow(ICS))

# ── 창별 rank-IC 부호 지속성 (PORT_t 와 동일 격자·동일 NW 추정량) ───────────
DATES <- sort(unique(IC$Date))
W <- dcast(IC, Date ~ Factor_Name, value.var = "ic")
setorder(W, Date); Wd <- as.matrix(W[, -1]); rownames(Wd) <- as.character(W$Date)
make_bounds <- function(n, WW) { b <- list(); e <- n
  while (e - WW + 1L >= 1L) { b[[length(b)+1L]] <- c(e-WW+1L, e); e <- e-WW }; rev(b) }
win_t <- function(v, bnd, mo) vapply(bnd, function(ix) { x <- v[ix[1]:ix[2]]
  xv <- x[is.finite(x)]
  if (length(xv) < mo || length(xv)/(ix[2]-ix[1]+1L) < 0.90) return(NA_real_)
  nw_t(xv) }, numeric(1))
pairs_of <- function(TT) rbindlist(lapply(seq_len(nrow(TT)-1L), function(k) {
  tk <- TT[k,]; tn <- TT[k+1L,]; ok <- is.finite(tk) & is.finite(tn)
  if (!any(ok)) return(NULL)
  data.table(Factor_Name = colnames(TT)[ok], k = k, t_k = tk[ok], t_next = tn[ok]) }))
CMP <- rbindlist(lapply(names(GRIDS), function(nm) {
  g <- GRIDS[[nm]]; bnd <- make_bounds(nrow(Wd), g$W)
  TT <- vapply(colnames(Wd), function(f) win_t(Wd[, f], bnd, g$min_obs), numeric(length(bnd)))
  if (is.null(dim(TT))) TT <- matrix(TT, nrow = length(bnd), dimnames = list(NULL, colnames(Wd)))
  P <- pairs_of(TT)
  data.table(grid = nm, basis = "rank_IC", n_pairs = nrow(P),
             p_persist = mean(sign(P$t_k) == sign(P$t_next)),
             share_pos = mean(TT > 0, na.rm = TRUE))
}))
PORTC <- rbindlist(lapply(names(GRIDS), function(nm) {
  P <- P1R$PR[[nm]]
  data.table(grid = nm, basis = "PORT_t", n_pairs = nrow(P),
             p_persist = mean(sign(P$t_k) == sign(P$t_next)),
             share_pos = mean(P1R$TG[[nm]]$t > 0, na.rm = TRUE)) }))
WALL <- rbind(PORTC, CMP)[order(grid, basis)]
print(WALL)
for (nm in names(GRIDS)) say("전이 벽 지속성[%s]: rank-IC 부호 %.3f vs PORT_t 부호 %.3f (Δ %+.3f)",
    nm, CMP[grid == nm, p_persist], PORTC[grid == nm, p_persist],
    CMP[grid == nm, p_persist] - PORTC[grid == nm, p_persist])

# IC 창 t 와 PORT_t 창 t 의 동시 관계 (같은 창에서 신호가 강하면 포트도 강한가)
J <- merge(P1R$PR$primary[, .(Factor_Name, k, port_t_k = t_k, port_t_next = t_next)],
           { g <- GRIDS$primary; bnd <- make_bounds(nrow(Wd), g$W)
             TT <- vapply(colnames(Wd), function(f) win_t(Wd[, f], bnd, g$min_obs), numeric(length(bnd)))
             if (is.null(dim(TT))) TT <- matrix(TT, nrow = length(bnd), dimnames = list(NULL, colnames(Wd)))
             pairs_of(TT)[, .(Factor_Name, k, ic_t_k = t_k, ic_t_next = t_next)] },
           by = c("Factor_Name", "k"))
say("동시 상관: cor(ic_t_k, port_t_k) = %.3f | 교차 예측 cor(ic_t_k, port_t_next) = %.3f",
    cor(J$ic_t_k, J$port_t_k, use = "complete.obs"),
    cor(J$ic_t_k, J$port_t_next, use = "complete.obs"))
say("ic_t_k 부호가 port_t_next 부호를 맞히는 비율 = %.3f (PORT_t 자기 예측 %.3f)",
    mean(sign(J$ic_t_k) == sign(J$port_t_next)), mean(sign(J$port_t_k) == sign(J$port_t_next)))

write_parquet(IC, file.path(OUT, "rank_ic_panel.parquet"))
saveRDS(list(ic_summary = ICS, wall = WALL, joint = J,
             pool_rank_ic_median = median(ICS$mean_ic),
             pool_icir_median = median(ICS$icir),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "rankic_results.rds"))
say("저장 — rank_ic_panel.parquet + rankic_results.rds")
