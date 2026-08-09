#==============================================================================
# b3_population_and_guard.R — b2 자가정정 + 재측정
#
# ★b2 에서 stale_now_med = 404일 · frac_same_end = 0.63 · span_med = 0 이 나왔다.
#   이는 창 길이 문제가 아니라 **내가 모집단을 가정하고 쟀기** 때문이다
#   (전 2744종목 × 318개월 격자에 roll=TRUE 를 걸면, 커버리지가 오래전 끊긴
#    종목도 "마지막 관측"으로 매번 끌려온다).
#   ⇒ 측정 첫 출력은 입력 실측이어야 한다. 여기서 모집단부터 잰다.
#
# ★그런데 이것은 측정 오류인 동시에 **두 번째 결함의 발견**일 수 있다:
#   현재/lag 끝점이 같은 행이면(same_endpoint) 창 길이와 무관하게 SE02 = 0 이다.
#   생산자(compute_crowding)는 date_rank==1 을 stale 종목에도 그대로 적용한다.
#   저장 산출물의 행수가 어느 모집단과 맞는지로 이를 판정한다.
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus")
FDB  <- file.path(ROOT, ".cache/factor_db")
TOL  <- 1e-12
LAGS <- c(21L, 35L, 63L, 91L, 126L, 252L)
K1_MED_REV <- 1.0; K1_FRAC_REV <- 0.80; K2_MAX_ZERO <- 0.20
K4_MAX_OVERSHOOT <- 10L; K4_MAX_STALE <- 10L; K5_MAX_RHO <- 0.90

rd_metric <- function(m) {
  h <- as.data.table(read_parquet(file.path(CD, paste0(m, ".parquet"))))
  h[, Date := as.Date(Date)]
  h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker", "Date")); h[]
}
E <- rd_metric("eps_1y")
E[, prev_v := shift(value), by = Ticker]
E[, chg := as.integer(!is.na(prev_v) & abs(value - prev_v) > TOL)]
E[, ccum := cumsum(chg), by = Ticker]
E[, obs_date := Date]; setkeyv(E, c("Ticker", "Date"))

led <- fread(file.path(FDB, "emission_ledger.csv"))
yms <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
month_end <- function(ym) {
  y <- as.integer(substr(as.character(ym),1,4)); m <- as.integer(substr(as.character(ym),5,6))
  (if (m == 12L) as.Date(sprintf("%d-01-01", y+1L)) else as.Date(sprintf("%d-%02d-01", y, m+1L))) - 1L
}
SIG <- data.table(ym = yms, sig = as.Date(vapply(yms, function(z) as.numeric(month_end(z)), 0), origin="1970-01-01"))
TK <- unique(E$Ticker)
mkQ <- function(off) {
  q <- CJ(Ticker = TK, i = seq_len(nrow(SIG)))
  q[, sig := SIG$sig[i]][, ym := SIG$ym[i]][, Date := sig - off][, i := NULL]
  setkeyv(q, c("Ticker","Date")); q[]
}
CUR <- E[mkQ(0L), roll = TRUE][!is.na(obs_date),
        .(Ticker, ym, sig, v_now = value, d_now = obs_date, cc_now = ccum, v_prevrow = prev_v)]
CUR[, stale := as.integer(sig - d_now)]

#==============================================================================
# G1 — 모집단 실측: 저장된 SE02 행수는 어느 모집단과 맞는가
#==============================================================================
SC <- fread(file.path(OUT, "b1_d_stored_se02_all_months.csv"))
pop <- CUR[, .(n_any = .N,
               n_le31 = sum(stale <= 31L), n_le63 = sum(stale <= 63L),
               n_le92 = sum(stale <= 92L), n_le366 = sum(stale <= 366L),
               stale_p50 = as.numeric(median(stale)),
               stale_p90 = as.numeric(quantile(stale,.90))), by = ym]
G1 <- merge(SC[, .(ym, n_stored = n)], pop, by = "ym")
cat("== G1 저장 SE02 행수 vs 모집단 후보 (전체 318개월 집계) ==\n")
cat(sprintf("  중앙값: stored=%.0f  any=%.0f  <=31d=%.0f  <=63d=%.0f  <=92d=%.0f  <=366d=%.0f\n",
            median(G1$n_stored), median(G1$n_any), median(G1$n_le31), median(G1$n_le63),
            median(G1$n_le92), median(G1$n_le366)))
for (cc in c("n_any","n_le31","n_le63","n_le92","n_le366")) {
  cat(sprintf("  |stored - %s| : median=%.0f  mean=%.0f  rho=%.4f\n", cc,
              median(abs(G1$n_stored - G1[[cc]])), mean(abs(G1$n_stored - G1[[cc]])),
              suppressWarnings(cor(G1$n_stored, G1[[cc]], method="spearman"))))
}
print(G1[ym %in% c(200812, 201403, 202006, 202606)])
fwrite(G1, file.path(OUT, "b3_g1_population.csv"))

#==============================================================================
# G2 — 재측정: liveness guard(stale <= 31d) 적용 후 bakeoff
#   ★guard 는 창 길이와 **직교**하는 별개 수리축이다. 둘을 분리해 보고한다.
#==============================================================================
V1 <- rd_metric("eps_chg_1m"); setnames(V1,"value","vendor_1m"); V1[, obs_date := Date]
setkeyv(V1, c("Ticker","Date"))
V3 <- rd_metric("eps_chg_3m"); setnames(V3,"value","vendor_3m"); V3[, obs_date := Date]
setkeyv(V3, c("Ticker","Date"))
VN1 <- V1[mkQ(0L), roll=TRUE][!is.na(obs_date), .(Ticker, ym, vendor_1m,
          v1_stale = as.integer(sig - obs_date))]
VN3 <- V3[mkQ(0L), roll=TRUE][!is.na(obs_date), .(Ticker, ym, vendor_3m,
          v3_stale = as.integer(sig - obs_date))]

GUARD <- 31L
run_bakeoff <- function(cur, tag) {
  out <- list(); rr <- list()
  for (L in LAGS) {
    LG <- E[mkQ(L), roll=TRUE][!is.na(obs_date), .(Ticker, ym, v_lag = value,
                                                   d_lag = obs_date, cc_lag = ccum)]
    J <- merge(cur, LG, by = c("Ticker","ym"))
    d <- J[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
    d[, se := (v_now - v_lag)/abs(v_lag)]; d <- d[is.finite(se)]
    if (!nrow(d)) next
    d[, rev_in_win := cc_now - cc_lag]
    out[[length(out)+1L]] <- d[, .(arm = sprintf("L%d", L), n = .N,
        frac_zero = mean(abs(se) < TOL), n_distinct = uniqueN(round(se,12)),
        q01 = as.numeric(quantile(se,.01)), q99 = as.numeric(quantile(se,.99)),
        rev_med = as.numeric(median(rev_in_win)), frac_rev_ge1 = mean(rev_in_win >= 1L),
        frac_same_end = mean(d_now == d_lag),
        overshoot_med = as.numeric(median(as.integer((sig - L) - d_lag))),
        stale_now_med = as.numeric(median(as.integer(sig - d_now))),
        span_med = as.numeric(median(as.integer(d_now - d_lag)))), by = .(ym, sig)]
    a <- merge(d, VN1, by=c("Ticker","ym")); b <- merge(d, VN3, by=c("Ticker","ym"))
    if (tag == "guarded") { a <- a[v1_stale <= GUARD]; b <- b[v3_stale <= GUARD] }
    r1 <- a[, .(rho = if (.N>30L && sd(se)>TOL && sd(vendor_1m,na.rm=TRUE)>TOL)
                 suppressWarnings(cor(se, vendor_1m, method="spearman", use="complete.obs")) else NA_real_), by=ym]
    r3 <- b[, .(rho = if (.N>30L && sd(se)>TOL && sd(vendor_3m,na.rm=TRUE)>TOL)
                 suppressWarnings(cor(se, vendor_3m, method="spearman", use="complete.obs")) else NA_real_), by=ym]
    rr[[length(rr)+1L]] <- data.table(arm = sprintf("L%d", L),
        rho_v1m_med = median(r1$rho, na.rm=TRUE), rho_v1m_p95 = as.numeric(quantile(r1$rho,.95,na.rm=TRUE)),
        rho_v3m_med = median(r3$rho, na.rm=TRUE), rho_v3m_p95 = as.numeric(quantile(r3$rho,.95,na.rm=TRUE)))
  }
  # 현행 인접-행 기준선
  B <- cur[!is.na(v_now) & !is.na(v_prevrow) & abs(v_prevrow) > 1e-8]
  B[, se := (v_now - v_prevrow)/abs(v_prevrow)]; B <- B[is.finite(se)]
  base <- B[, .(arm = "BASE_adjacent_row", n = .N, frac_zero = mean(abs(se) < TOL),
                n_distinct = uniqueN(round(se,12)),
                q01 = as.numeric(quantile(se,.01)), q99 = as.numeric(quantile(se,.99)),
                rev_med = NA_real_, frac_rev_ge1 = NA_real_, frac_same_end = NA_real_,
                overshoot_med = NA_real_,
                stale_now_med = as.numeric(median(as.integer(sig - d_now))),
                span_med = NA_real_), by = .(ym, sig)]
  per <- rbindlist(c(list(base), out), fill = TRUE)
  agg <- per[, .(n_months = .N, n_med = as.numeric(median(n)),
      frac_zero_med = median(frac_zero), frac_zero_max = max(frac_zero),
      n_dead = sum(abs(q99-q01) < TOL),
      rev_med_med = median(rev_med), frac_rev_ge1_med = median(frac_rev_ge1),
      frac_rev_ge1_min = min(frac_rev_ge1), frac_same_end_med = median(frac_same_end),
      overshoot_med = median(overshoot_med), stale_now_med = median(stale_now_med),
      span_med = median(span_med), ndist_med = as.numeric(median(n_distinct))), by = arm]
  agg <- merge(agg, rbindlist(rr), by = "arm", all.x = TRUE)
  agg <- agg[match(c("BASE_adjacent_row", sprintf("L%d", LAGS)), arm)]
  agg[, `:=`(
    K1 = !is.na(rev_med_med) & rev_med_med >= K1_MED_REV & frac_rev_ge1_med >= K1_FRAC_REV,
    K2 = frac_zero_med <= K2_MAX_ZERO,
    K3 = n_dead == 0L,
    K4 = !is.na(overshoot_med) & overshoot_med <= K4_MAX_OVERSHOOT & stale_now_med <= K4_MAX_STALE,
    K5 = pmax(abs(rho_v1m_p95), abs(rho_v3m_p95), na.rm = TRUE) < K5_MAX_RHO)]
  agg[, ALLPASS := K1 & K2 & K3 & K4 & K5]
  list(per = per, agg = agg)
}

cat("\n\n############ A) guard 없음 (현행 모집단 = 생산자 재현) ############\n")
RA <- run_bakeoff(copy(CUR), "unguarded")
print(RA$agg[, .(arm, n_med, frac_zero_med, n_dead, rev_med_med, frac_rev_ge1_med,
                 frac_same_end_med, stale_now_med, span_med)])
print(RA$agg[, .(arm, K1, K2, K3, K4, K5, ALLPASS)])

cat(sprintf("\n\n############ B) liveness guard 적용 (stale <= %dd) ############\n", GUARD))
RB <- run_bakeoff(CUR[stale <= GUARD], "guarded")
print(RB$agg[, .(arm, n_med, frac_zero_med, n_dead, rev_med_med, frac_rev_ge1_med,
                 frac_same_end_med, stale_now_med, span_med)])
cat("\n-- 창 기하 + 중복(K5) --\n")
print(RB$agg[, .(arm, overshoot_med, ndist_med, rho_v1m_med, rho_v1m_p95,
                 rho_v3m_med, rho_v3m_p95)])
cat("\n-- 기준 판정 (측정 전 고정) --\n")
print(RB$agg[, .(arm, K1, K2, K3, K4, K5, ALLPASS)])

fwrite(RA$agg, file.path(OUT, "b3_agg_unguarded.csv"))
fwrite(RB$agg, file.path(OUT, "b3_agg_guarded.csv"))
fwrite(RB$per, file.path(OUT, "b3_permonth_guarded.csv"))

# 3월 최악 케이스 (guard 적용)
MAR <- RB$per[substr(as.character(ym),5,6) == "03",
    .(n_months = .N, n_med = as.numeric(median(n)), frac_zero_med = median(frac_zero),
      frac_zero_max = max(frac_zero), n_dead = sum(abs(q99-q01) < TOL),
      frac_rev_ge1 = median(frac_rev_ge1)), by = arm]
MAR <- MAR[match(c("BASE_adjacent_row", sprintf("L%d", LAGS)), arm)]
cat("\n-- 3월만 (개정 최희소월, guard 적용) --\n"); print(MAR)
fwrite(MAR, file.path(OUT, "b3_march_guarded.csv"))

cat("\n[b3 완료]\n")
