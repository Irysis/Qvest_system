#==============================================================================
# b2_bakeoff.R — SE02 창 길이 bakeoff (FQ-222 (A))
#
# ★선택 기준은 **측정 전에 고정**했다. 아래 K1~K5 만으로 고른다.
#   신호력(IC / PORT_t / 수익)은 일절 쓰지 않는다 — 그건 사후선택이다.
#
#   K1 창-내 개정 존재 : median(rev_in_window) >= 1  AND  frac(rev>=1) >= 0.80
#   K2 영값 팽창 해소  : frac_exact_zero <= 0.20
#   K3 죽은 달 소멸    : 전 검증월에서 Z 산출 가능 (q01 != q99 — 아래 기전 참조)
#   K4 앵커 신선도     : median(명목앵커 - 실제앵커일) <= 10일 AND
#                        median(sig_d - 현재관측일) <= 10일
#   K5 비중복          : |rho_spearman| < 0.90  vs 벤더 eps_chg_1m(C02/M27),
#                                                    eps_chg_3m(C03)
#   동점 처리: K1~K5 전건 통과 후보 중 → 같은 계열 기존 lag(63일: C14/C17/
#              M26/M28) 일치 → 그 다음 짧은 창
#
# ★K3 기전(실측 확정, b1): factor_db_builder.R:672-687 이 Raw 를 1/99 로
#   winsorize 한 뒤 z 를 낸다. 값의 99% 가 정확히 0 이면 q01 == q99 == 0 이라
#   전 종목 Raw_W 가 상수 → sd < 1e-12 → Z 전건 NA → Coverage FALSE.
#   즉 "죽은 달" 은 sd=0 이 아니라 **winsorize 후 상수화**다. 저장 실측과 일치:
#   죽은 달 frac_zero >= 0.988 / 산 달 <= 0.959.
#
# 읽기 전용. 재빌드 없음(save=FALSE 도 호출 안 함 — 원천 패널만 읽는다).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus")
FDB  <- file.path(ROOT, ".cache/factor_db")
TOL  <- 1e-12
LAGS <- c(21L, 35L, 63L, 91L, 126L, 252L)

# ── 기준 상수 (측정 전 고정) ────────────────────────────────────────────────
K1_MED_REV <- 1.0; K1_FRAC_REV <- 0.80
K2_MAX_ZERO <- 0.20
K4_MAX_OVERSHOOT <- 10L; K4_MAX_STALE <- 10L
K5_MAX_RHO <- 0.90

rd_metric <- function(m) {
  p <- file.path(CD, paste0(m, ".parquet"))
  if (!file.exists(p)) stop(sprintf("[STOP] 원천 부재: %s", p))
  h <- as.data.table(read_parquet(p)); h[, Date := as.Date(Date)]
  h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker", "Date")); h[]
}

E <- rd_metric("eps_1y")
if (!nrow(E)) stop("[STOP] eps_1y 0행 — 0은 결론이 아니라 정지 신호")
E[, prev_v := shift(value), by = Ticker]
E[, chg := as.integer(!is.na(prev_v) & abs(value - prev_v) > TOL)]
E[, ccum := cumsum(chg), by = Ticker]     # 개정 누적 카운트
E[, obs_date := Date]
setkeyv(E, c("Ticker", "Date"))

V1 <- rd_metric("eps_chg_1m"); setnames(V1, "value", "vendor_1m")
V1[, obs_date := Date]; setkeyv(V1, c("Ticker", "Date"))
V3 <- rd_metric("eps_chg_3m"); setnames(V3, "value", "vendor_3m")
V3[, obs_date := Date]; setkeyv(V3, c("Ticker", "Date"))

# ── 검증월: SE02 배출 318개월 전부 (월말 달력일 기준) ───────────────────────
led <- fread(file.path(FDB, "emission_ledger.csv"))
yms <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
if (!length(yms)) stop("[STOP] SE02 배출 원장 0건 — 정지 신호")
month_end <- function(ym) {
  y <- as.integer(substr(as.character(ym), 1, 4)); m <- as.integer(substr(as.character(ym), 5, 6))
  nxt <- if (m == 12L) as.Date(sprintf("%d-01-01", y + 1L)) else as.Date(sprintf("%d-%02d-01", y, m + 1L))
  nxt - 1L
}
SIG <- data.table(ym = yms, sig = as.Date(vapply(yms, function(z) as.numeric(month_end(z)), 0), origin = "1970-01-01"))
cat(sprintf("검증월 %d개 (%s .. %s)\n", nrow(SIG), min(SIG$ym), max(SIG$ym)))

TK <- unique(E$Ticker)
mkQ <- function(offset) {
  q <- CJ(Ticker = TK, i = seq_len(nrow(SIG)))
  q[, sig := SIG$sig[i]][, ym := SIG$ym[i]][, Date := sig - offset][, i := NULL]
  setkeyv(q, c("Ticker", "Date")); q[]
}

roll_pick <- function(panel, q) {
  r <- panel[q, roll = TRUE]
  r[!is.na(obs_date)]
}

# 현재 끝점 (offset 0) — lag 후보 전부가 공유
CUR <- roll_pick(E, mkQ(0L))[, .(Ticker, ym, sig, v_now = value, d_now = obs_date,
                                 cc_now = ccum, v_prevrow = prev_v)]
cat(sprintf("현재 끝점 %s행\n", format(nrow(CUR), big.mark = ",")))

# 벤더 참조 (K5)
VN1 <- roll_pick(V1, mkQ(0L))[, .(Ticker, ym, vendor_1m)]
VN3 <- roll_pick(V3, mkQ(0L))[, .(Ticker, ym, vendor_3m)]

#------------------------------------------------------------------------------
# 후보 평가
#------------------------------------------------------------------------------
eval_arm <- function(dt, arm_label) {
  # dt: Ticker, ym, sig, v_now, d_now, cc_now, v_lag, d_lag, cc_lag
  d <- dt[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
  if (!nrow(d)) return(NULL)
  d[, se := (v_now - v_lag) / abs(v_lag)]
  d <- d[is.finite(se)]
  d[, rev_in_win := cc_now - cc_lag]
  d[, same_endpoint := d_now == d_lag]
  d[, overshoot := as.integer((sig - as.integer(sub("^L", "", arm_label))) - d_lag)]
  d[, stale_now := as.integer(sig - d_now)]
  d[, span := as.integer(d_now - d_lag)]
  d[, .(arm = arm_label, n = .N,
        frac_zero      = mean(abs(se) < TOL),
        n_distinct     = uniqueN(round(se, 12)),
        sd_se          = sd(se),
        q01            = as.numeric(quantile(se, .01)),
        q99            = as.numeric(quantile(se, .99)),
        rev_med        = as.numeric(median(rev_in_win)),
        frac_rev_ge1   = mean(rev_in_win >= 1L),
        frac_same_end  = mean(same_endpoint),
        overshoot_med  = as.numeric(median(overshoot)),
        stale_now_med  = as.numeric(median(stale_now)),
        span_med       = as.numeric(median(span))), by = .(ym, sig)]
}

res <- list()
rho <- list()
for (L in LAGS) {
  LG <- roll_pick(E, mkQ(L))[, .(Ticker, ym, v_lag = value, d_lag = obs_date, cc_lag = ccum)]
  J  <- merge(CUR, LG, by = c("Ticker", "ym"))
  lab <- sprintf("L%d", L)
  res[[lab]] <- eval_arm(J, lab)
  # K5: 벤더 대비 rank 상관 (월별)
  d <- J[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
  d[, se := (v_now - v_lag) / abs(v_lag)]; d <- d[is.finite(se)]
  a <- merge(d, VN1, by = c("Ticker", "ym")); b <- merge(d, VN3, by = c("Ticker", "ym"))
  r1 <- a[, .(n = .N, rho = if (.N > 30L && sd(se) > TOL && sd(vendor_1m, na.rm = TRUE) > TOL)
                suppressWarnings(cor(se, vendor_1m, method = "spearman", use = "complete.obs")) else NA_real_), by = ym]
  r3 <- b[, .(n = .N, rho = if (.N > 30L && sd(se) > TOL && sd(vendor_3m, na.rm = TRUE) > TOL)
                suppressWarnings(cor(se, vendor_3m, method = "spearman", use = "complete.obs")) else NA_real_), by = ym]
  rho[[lab]] <- data.table(arm = lab,
    rho_v1m_med = median(r1$rho, na.rm = TRUE), rho_v1m_p95 = as.numeric(quantile(r1$rho, .95, na.rm = TRUE)),
    rho_v3m_med = median(r3$rho, na.rm = TRUE), rho_v3m_p95 = as.numeric(quantile(r3$rho, .95, na.rm = TRUE)))
  cat(sprintf("  [%s] done\n", lab))
}

# 현행(인접 행) 기준선 — eps_1y 단독 재현
B <- CUR[!is.na(v_now) & !is.na(v_prevrow) & abs(v_prevrow) > 1e-8]
B[, se := (v_now - v_prevrow) / abs(v_prevrow)]; B <- B[is.finite(se)]
BASE <- B[, .(arm = "BASE_adjacent_row", n = .N,
              frac_zero = mean(abs(se) < TOL), n_distinct = uniqueN(round(se, 12)),
              sd_se = sd(se), q01 = as.numeric(quantile(se, .01)), q99 = as.numeric(quantile(se, .99)),
              rev_med = NA_real_, frac_rev_ge1 = NA_real_, frac_same_end = NA_real_,
              overshoot_med = NA_real_, stale_now_med = as.numeric(median(as.integer(sig - d_now))),
              span_med = NA_real_), by = .(ym, sig)]

ALL <- rbindlist(c(list(BASE), res), fill = TRUE)
fwrite(ALL, file.path(OUT, "b2_permonth_all_arms.csv"))

#------------------------------------------------------------------------------
# 재현 검증 (양성 대조): 내 기준선이 **저장된** SE02 를 실제로 재현하는가
#------------------------------------------------------------------------------
SC <- fread(file.path(OUT, "b1_d_stored_se02_all_months.csv"))
chk <- merge(BASE[, .(ym, frac_zero_repro = frac_zero)],
             SC[, .(ym, frac_zero_stored = frac_zero)], by = "ym")
cat(sprintf("\n== 재현 검증: 기준선 vs 저장값 frac_zero (n=%d월) ==\n", nrow(chk)))
cat(sprintf("  rho(spearman) = %.4f · mean|diff| = %.4f · median|diff| = %.4f\n",
            suppressWarnings(cor(chk$frac_zero_repro, chk$frac_zero_stored, method = "spearman")),
            mean(abs(chk$frac_zero_repro - chk$frac_zero_stored)),
            median(abs(chk$frac_zero_repro - chk$frac_zero_stored))))
fwrite(chk, file.path(OUT, "b2_reproduction_check.csv"))

#------------------------------------------------------------------------------
# 기준별 집계 + 판정
#------------------------------------------------------------------------------
dead_pred <- function(d) d[, sum(abs(q99 - q01) < TOL)]
AGG <- ALL[, .(
  n_months        = .N,
  n_med           = as.numeric(median(n)),
  frac_zero_med   = median(frac_zero),
  frac_zero_p90   = as.numeric(quantile(frac_zero, .90)),
  frac_zero_max   = max(frac_zero),
  n_months_zero_ge_098 = sum(frac_zero >= 0.98),
  n_months_dead_pred   = sum(abs(q99 - q01) < TOL),
  rev_med_med     = median(rev_med),
  frac_rev_ge1_med= median(frac_rev_ge1),
  frac_rev_ge1_min= min(frac_rev_ge1),
  frac_same_end_med = median(frac_same_end),
  overshoot_med   = median(overshoot_med),
  stale_now_med   = median(stale_now_med),
  span_med        = median(span_med),
  ndist_med       = as.numeric(median(n_distinct))), by = arm]
RHO <- rbindlist(rho)
AGG <- merge(AGG, RHO, by = "arm", all.x = TRUE)
ord <- c("BASE_adjacent_row", sprintf("L%d", LAGS))
AGG <- AGG[match(ord, arm)]

AGG[, K1_pass := !is.na(rev_med_med) & rev_med_med >= K1_MED_REV & frac_rev_ge1_med >= K1_FRAC_REV]
AGG[, K2_pass := frac_zero_med <= K2_MAX_ZERO]
AGG[, K3_pass := n_months_dead_pred == 0L]
AGG[, K4_pass := !is.na(overshoot_med) & overshoot_med <= K4_MAX_OVERSHOOT & stale_now_med <= K4_MAX_STALE]
AGG[, K5_pass := pmax(abs(rho_v1m_p95), abs(rho_v3m_p95), na.rm = TRUE) < K5_MAX_RHO]
AGG[, ALL_pass := K1_pass & K2_pass & K3_pass & K4_pass & K5_pass]

cat("\n================ BAKEOFF 결과 (318개월 집계) ================\n")
print(AGG[, .(arm, n_med, frac_zero_med, frac_zero_max, n_months_dead_pred,
               rev_med_med, frac_rev_ge1_med, frac_same_end_med)])
cat("\n-- 창 기하 + 중복 --\n")
print(AGG[, .(arm, overshoot_med, stale_now_med, span_med, ndist_med,
               rho_v1m_med, rho_v1m_p95, rho_v3m_med, rho_v3m_p95)])
cat("\n-- 기준 판정 --\n")
print(AGG[, .(arm, K1_pass, K2_pass, K3_pass, K4_pass, K5_pass, ALL_pass)])
fwrite(AGG, file.path(OUT, "b2_bakeoff_summary.csv"))

# 3월(개정 희소월) 별도 — K3 의 최악 케이스
MAR <- ALL[substr(as.character(ym), 5, 6) == "03",
           .(n_months = .N, frac_zero_med = median(frac_zero),
             frac_zero_max = max(frac_zero), n_dead = sum(abs(q99 - q01) < TOL),
             rev_med = median(rev_med), frac_rev_ge1 = median(frac_rev_ge1)), by = arm]
MAR <- MAR[match(ord, arm)]
cat("\n-- 3월만 (eps_1y 개정 최희소월: 전체 변경의 1.3%) --\n"); print(MAR)
fwrite(MAR, file.path(OUT, "b2_march_worstcase.csv"))

cat("\n[b2 완료]\n")
