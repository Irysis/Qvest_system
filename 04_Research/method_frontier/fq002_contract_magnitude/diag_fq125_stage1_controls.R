# =============================================================================
# diag_fq125_stage1_controls.R — WT-D20260803_008 통제 배터리
#
# 확정 수치(fq125_stage1_results.json)는 불변. 본 스크립트는 **해석 검증** 전용:
#   C0. 하네스 카나리아 — 알려진 look-ahead 스코어가 IC≈1 을 내는가 (측정기 생존 확인)
#   C1. 대안 배제: mega_led/broad_led 분리가 **사이즈 틸트** 만으로 재현되는가
#        (순수 1/Size 신호를 동일 유니버스·동일 국면버킷에 태워 대조)
#   C2. 사이즈-잔차화 후에도 분리가 남는가 (혐의 확인 통제)
#   C3. 국면 상태를 **사전관측 가능**하게 (t-1 mega_spread) 바꿔도 분리가 남는가
#        — 동월 mega_spread 는 홀딩월과 동시점이라 거래 불가 진단일 뿐
#   C4. 부기간·연도별 감쇠가 국면 구성으로 설명되는가 (mega_led 비중)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(2)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"

panelA <- as.data.table(read_parquet(file.path(OUTD, "panelx_A.parquet")))
Rg <- as.data.table(read_parquet(file.path(OUTD, "gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "gridx_bench.parquet")));   Bg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "gridx_liq.parquet")));     Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "gridx_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
SZ <- MEM[, .(Date, Ticker, Size)]
ym_of <- function(d) format(d, "%Y%m")
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 8) return(NA_real_)
  m <- mean(x); e <- x - m; v <- sum(e^2) / n
  for (l in 1:lag) { if (l >= n) break
    cv <- sum(e[1:(n - l)] * e[(l + 1):n]) / n; v <- v + 2 * (1 - l / (lag + 1)) * cv }
  se <- sqrt(v / n); if (!is.finite(se) || se <= 0) return(NA_real_); m / se
}
# 기준 스코어 패널 (run_fq125_stage1.R mk_scores 와 동일)
S <- merge(me_dates, panelA[, .(ym, Ticker, w_amt, w_ratio)], by = "ym")
S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
S <- S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0 & is.finite(Size),
       .(Date, Ticker, score, Size)]
M <- merge(S, Rg, by = c("Date", "Ticker"))
M <- M[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]

ic_by_month <- function(dt, sc = "score", min_n = 8L)
  dt[, .(n = .N, ic = if (.N >= min_n)
           suppressWarnings(cor(get(sc), Ret_1m, method = "spearman")) else NA_real_),
     by = Date][is.finite(ic)][order(Date)]
smry <- function(ics, lab) if (!nrow(ics)) list(label = lab, n = 0L) else
  list(label = lab, n = nrow(ics), mean_ic = mean(ics$ic),
       t_plain = mean(ics$ic) / sd(ics$ic) * sqrt(nrow(ics)), t_nw = nw_t(ics$ic),
       pos_share = mean(ics$ic > 0))
show <- function(s) cat(sprintf("  %-34s n=%3d meanIC=%+.5f t_plain=%+.3f t_NW=%+.3f pos=%.0f%%\n",
                                s$label, s$n, s$mean_ic, s$t_plain, s$t_nw, 100 * s$pos_share))

# ── C0. 하네스 카나리아 ─────────────────────────────────────────────────────
# 알려진 look-ahead: 스코어 = 당월 실현수익. IC 가 1 에 붙지 않으면 측정기가 죽은 것.
Mc <- copy(M); Mc[, score_la := Ret_1m]
can <- smry(ic_by_month(Mc, "score_la"), "CANARY: score = 당월 실현수익")
# 무정보 대조: 난수 스코어 → IC ≈ 0
set.seed(4242); Mc[, score_rn := runif(.N)]
can0 <- smry(ic_by_month(Mc, "score_rn"), "CANARY: score = 난수")
cat("[C0] 하네스 카나리아 (검사기 생존 확인)\n"); show(can); show(can0)
canary_ok <- is.finite(can$mean_ic) && can$mean_ic > 0.95 && abs(can0$mean_ic) < 0.05
cat(sprintf("[C0] → 카나리아 %s\n\n", ifelse(canary_ok, "PASS (IC 계산 살아있음)", "★FAIL — 측정기 의심")))

# ── 국면 라벨 (동월 = 진단 / t-1 = 사전관측) ────────────────────────────────
megasp <- local({
  X <- merge(Rg, SZ, by = c("Date", "Ticker"))
  X <- X[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
  X[, rk := frank(-Size, ties.method = "first"), by = Date]
  X[, .(mega_spread = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by = Date][order(Date)]
})
megasp[, mega_spread_lag1 := shift(mega_spread, 1)]
megasp[, mega_spread_tr3 := frollmean(shift(mega_spread, 1), 3)]

lab <- function(ics) merge(ics, megasp, by = "Date")
split_report <- function(ics, tag, col) {
  L <- lab(ics); L <- L[is.finite(get(col))]
  a <- smry(L[get(col) >  0][, .(Date, n, ic)], paste0(tag, " | ", col, ">0 (mega led)"))
  b <- smry(L[get(col) <= 0][, .(Date, n, ic)], paste0(tag, " | ", col, "<=0 (broad led)"))
  show(a); show(b)
  list(mega = a, broad = b, gap = if (a$n && b$n) b$mean_ic - a$mean_ic else NA_real_)
}

# ── C1. 대안 배제: 순수 1/Size 를 동일 유니버스에 ──────────────────────────
M[, inv_size := -Size]                      # 랭크 기준: 작을수록 상위 = 소형주 롱
ic_sz  <- ic_by_month(M, "inv_size")
ic_ctr <- ic_by_month(M, "score")
cat("[C1] 대안 배제 — 순수 사이즈 틸트가 같은 분리를 내는가\n")
show(smry(ic_ctr, "계약 score (base)")); show(smry(ic_sz, "순수 1/Size (동일 유니버스)"))
c1_ctr <- split_report(ic_ctr, "계약 score", "mega_spread")
c1_sz  <- split_report(ic_sz,  "순수 1/Size", "mega_spread")
cat(sprintf("[C1] gap(broad-mega): 계약 %+.5f vs 사이즈 %+.5f → 사이즈 설명비율 %.1f%%\n\n",
            c1_ctr$gap, c1_sz$gap, 100 * c1_sz$gap / c1_ctr$gap))

# ── C2. 사이즈-잔차화 (혐의 확인 통제) ──────────────────────────────────────
M[, `:=`(rz_score = { r <- frank(score); (r - mean(r)) / max(sd(r), 1e-12) },
         rz_isize = { r <- frank(-Size); (r - mean(r)) / max(sd(r), 1e-12) }), by = Date]
M[, resid_score := { fit <- lm(rz_score ~ rz_isize); as.numeric(residuals(fit)) }, by = Date]
ic_res <- ic_by_month(M, "resid_score")
cat("[C2] 사이즈-잔차화 후\n")
show(smry(ic_res, "size-residualized score"))
c2 <- split_report(ic_res, "size-resid", "mega_spread")
cat(sprintf("[C2] 잔차화 후 gap = %+.5f (원 %+.5f, 보존율 %.1f%%)\n\n",
            c2$gap, c1_ctr$gap, 100 * c2$gap / c1_ctr$gap))
# 단면 상관 (score vs 1/Size)
xs <- M[, .(rho = suppressWarnings(cor(rz_score, rz_isize, method = "spearman"))), by = Date]
cat(sprintf("[C2] score~1/Size 월별 단면상관: 평균 %+.4f (min %+.3f / max %+.3f)\n\n",
            mean(xs$rho), min(xs$rho), max(xs$rho)))

# ── C3. 사전관측 가능한 국면 라벨 ───────────────────────────────────────────
cat("[C3] 국면 상태를 t-1 (사전관측 가능) 로 바꾸면 분리가 남는가\n")
c3_lag1 <- split_report(ic_ctr, "계약 score", "mega_spread_lag1")
c3_tr3  <- split_report(ic_ctr, "계약 score", "mega_spread_tr3")
cat(sprintf("[C3] gap: 동월 %+.5f | t-1 %+.5f | t-1..t-3 평균 %+.5f\n\n",
            c1_ctr$gap, c3_lag1$gap, c3_tr3$gap))

# ── C4. 감쇠와 국면 구성 ───────────────────────────────────────────────────
LL <- lab(ic_ctr)
LL[, era := fifelse(Date >= as.Date("2024-07-01"), "pilot", "new")]
comp <- LL[, .(n = .N, share_mega_led = mean(mega_spread > 0), mean_ic = mean(ic),
               mean_megaspread = mean(mega_spread)), by = era]
compy <- LL[, .(n = .N, share_mega_led = mean(mega_spread > 0), mean_ic = mean(ic)),
            by = .(yr = format(Date, "%Y"))][order(yr)]
cat("[C4] 구간별 mega_led 비중 vs mean IC\n"); print(comp); print(compy)
# 파일럿 내부 first12/last12
pil <- LL[era == "pilot"][order(Date)]
if (nrow(pil) >= 24) {
  h <- list(first12 = pil[1:12], last12 = pil[13:24])
  cat(sprintf("[C4] 파일럿 first12 meanIC=%+.5f (mega_led %.0f%%) | last12 meanIC=%+.5f (mega_led %.0f%%)\n",
              mean(h$first12$ic), 100 * mean(h$first12$mega_spread > 0),
              mean(h$last12$ic), 100 * mean(h$last12$mega_spread > 0)))
}

out <- list(measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            purpose = "해석 검증 통제 배터리 — 확정 수치 불변",
            C0_canary = list(lookahead = can, random = can0, pass = canary_ok),
            C1_size_alternative = list(base = smry(ic_ctr, "contract"), pure_size = smry(ic_sz, "inv_size"),
                                       split_contract = c1_ctr, split_size = c1_sz,
                                       size_explained_share = c1_sz$gap / c1_ctr$gap),
            C2_size_residualized = list(summary = smry(ic_res, "resid"), split = c2,
                                        gap_retention = c2$gap / c1_ctr$gap,
                                        cross_sec_rho_mean = mean(xs$rho)),
            C3_exante_regime = list(contemporaneous_gap = c1_ctr$gap, lag1 = c3_lag1, trailing3 = c3_tr3),
            C4_composition = list(by_era = comp, by_year = compy))
write_json(out, file.path(OUTD, "fq125_stage1_controls.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 8, null = "null")
cat("\n→ ", file.path(OUTD, "fq125_stage1_controls.json"), "\n")
