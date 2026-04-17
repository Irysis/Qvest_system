## 작업 1: STR_930 M3 포트폴리오 편입 시뮬레이션
## 기존 3-sleeve(VDplus+Q07) + STR_930 M3 추가 4-sleeve 비교
## PIT: C9 모든 오버레이 t-1 lag, expanding window
## 배분안: (A) VDplus 60% + Q07 15% + STR_930_M3 25%
##          (B) VDplus 55% + Q07 15% + STR_930_M3 15% + MLRA 15%  [MLRA 없으면 대안]

cat("=== 포트폴리오 편입 시뮬레이션: STR_930 M3 4-sleeve ===\n\n")

library(data.table)
library(zoo)
library(xts)
options(scipen = 999)

# ===================================================================
# 경로 설정
# ===================================================================
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SCRIPT_DIR <- file.path(ROOT, "04_Research/strategies/portfolio_sim_930")

PG2_NAV  <- file.path(ROOT, "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
DEF_CSV  <- file.path(ROOT, "04_Research/strategies/STR_1662_defense_D25_Q07/output/performance_STR_1662a.csv")
STR930_RDS <- file.path(ROOT, "04_Research/strategies/STR_930_oc_foreign_esbr/sim_result.rds")
OUT_DIR  <- SCRIPT_DIR

# ===================================================================
# 1. 데이터 로드 (1회)
# ===================================================================
cat("[1] 데이터 로드...\n")

## STR_1631 VDplus (PG2 best variant)
pg2 <- fread(PG2_NAV)
pg2[, Date := as.Date(Date)]
setkey(pg2, Date)
s1631_daily <- pg2[, .(Date, ret = Ret_vdp)]
cat(sprintf("  STR_1631 VDplus: %d rows | %s ~ %s\n",
    nrow(s1631_daily), min(s1631_daily$Date), max(s1631_daily$Date)))

## STR_1662a Q07 defense (월별 수익률)
def_raw <- fread(DEF_CSV)
def_raw[, Date := as.Date(Date)]
setkey(def_raw, Date)
# 마지막 미완성 월 제외
def_raw <- def_raw[!(port_ret == 0 & Date == max(Date))]
cat(sprintf("  STR_1662a (Q07): %d rows | %s ~ %s\n",
    nrow(def_raw), min(def_raw$Date), max(def_raw$Date)))

## STR_930 M3: sim_result.rds → DD Brake M3 재계산
sim930 <- readRDS(STR930_RDS)
ret930_daily <- as.numeric(sim930$strategy_xts)
# xts 마스킹 우회: as.Date(index()) 대신 직접 변환
dts930 <- base::as.Date(base::as.numeric(zoo::index(sim930$strategy_xts)),
                        origin = "1970-01-01")
cat(sprintf("  STR_930 daily: %d rows | %s ~ %s\n",
    length(ret930_daily), dts930[1], tail(dts930, 1)))

# ===================================================================
# 2. STR_930 M3 DD Brake 재계산 (C9: t-1 lag)
# M3: threshold 6%, full_cash 20%
# ===================================================================
cat("\n[2] STR_930 M3 DD Brake 재계산 (threshold=6%, full_cash=20%)...\n")

n_f <- length(ret930_daily)
nav930 <- cumprod(1 + ret930_daily)
dd_pct <- 1 - nav930 / cummax(nav930)

# C9 엄격 적용: t-1 lag
dd_lag <- c(0, head(dd_pct, -1))

threshold <- 0.06
full_cash  <- 0.20

exposure <- ifelse(
  dd_lag <= threshold,  1.0,
  ifelse(
    dd_lag >= full_cash, 0.0,
    1.0 - (dd_lag - threshold) / (full_cash - threshold)
  )
)

ret930_m3_daily <- ret930_daily * exposure

# 성과 확인
nav_m3 <- cumprod(1 + ret930_m3_daily)
mdd_m3 <- -max(1 - nav_m3 / cummax(nav_m3)) * 100
cagr_m3 <- (tail(nav_m3, 1)^(252 / n_f) - 1) * 100
sr_m3 <- mean(ret930_m3_daily) / sd(ret930_m3_daily) * sqrt(252)
cat(sprintf("  M3 재계산: CAGR=%.2f%% | SR=%.3f | MDD=%.2f%%\n",
    cagr_m3, sr_m3, mdd_m3))

# ===================================================================
# 3. 월별 수익률 집계
# ===================================================================
cat("\n[3] 월별 집계...\n")

# STR_1631 VDplus 월별
s1631_daily[, ym := format(Date, "%Y-%m")]
s1631_mon <- s1631_daily[, .(
  Date    = max(Date),
  ret_vdp = prod(1 + ret, na.rm = TRUE) - 1
), by = ym]
setkey(s1631_mon, Date)

# STR_1662a Q07 월별 (이미 월별)
def_mon <- def_raw[, .(Date, ret_q07 = port_ret)]
setkey(def_mon, Date)

# STR_930 M3 월별
dt930 <- data.table(Date = dts930, ret = ret930_m3_daily)
dt930[, ym := format(Date, "%Y-%m")]
mon930 <- dt930[, .(
  Date    = max(Date),
  ret_930 = prod(1 + ret, na.rm = TRUE) - 1
), by = ym]
setkey(mon930, Date)

cat(sprintf("  VDplus: %d개월 | Q07: %d개월 | STR_930_M3: %d개월\n",
    nrow(s1631_mon), nrow(def_mon), nrow(mon930)))

# 공통 기간 병합 (3-sleeve 기준: VDplus + Q07)
mon3 <- merge(
  s1631_mon[, .(Date, ret_vdp)],
  def_mon[, .(Date, ret_q07)],
  by = "Date", all = FALSE
)
# 4-sleeve: + STR_930_M3
mon4 <- merge(
  mon3,
  mon930[, .(Date, ret_930)],
  by = "Date", all = FALSE
)
setkey(mon4, Date)

cat(sprintf("  3-sleeve 공통: %d개월 | 4-sleeve 공통: %d개월\n",
    nrow(mon3), nrow(mon4)))
cat(sprintf("  4-sleeve 기간: %s ~ %s\n",
    min(mon4$Date), max(mon4$Date)))

# ===================================================================
# 4. 성과 계산 헬퍼
# ===================================================================
calc_perf <- function(rets, label = "Portfolio") {
  n  <- length(rets)
  if (n < 12) return(list(Label=label, CAGR=NA, AnnVol=NA, SR=NA, MDD=NA, Calmar=NA))
  yr   <- n / 12
  cr   <- prod(1 + rets, na.rm = TRUE)
  cagr <- (cr^(1/yr) - 1) * 100
  mu   <- mean(rets, na.rm = TRUE) * 12 * 100
  sig  <- sd(rets, na.rm = TRUE) * sqrt(12) * 100
  sr   <- mu / sig
  nav  <- cumprod(1 + rets)
  dd   <- 1 - nav / cummax(nav)
  mdd  <- -max(dd) * 100
  cal  <- (cagr / 100) / (-mdd / 100)
  list(Label=label, CAGR=round(cagr,2), AnnVol=round(sig,2),
       SR=round(sr,3), MDD=round(mdd,2), Calmar=round(cal,3))
}

# 연별 수익률
annual_ret <- function(rets, dates) {
  dt_r <- data.table(Date=as.Date(dates), ret=rets)
  dt_r[, yr := year(Date)]
  dt_r[, .(ann_ret = (prod(1+ret,na.rm=TRUE)-1)*100), by=yr]
}

# 상관계수 행렬
corr_mat <- function(dt) {
  round(cor(dt[, .(ret_vdp, ret_q07, ret_930)], use="complete.obs"), 3)
}

# ===================================================================
# 5. 배분 시나리오 비교
# ===================================================================
cat("\n[4] 배분 시나리오 비교...\n")

scenarios <- list(
  # 기준: 현재 3-sleeve 대표 (포트폴리오 3-sleeve 최적 결과에서 SR 최고값)
  # portfolio_opt_3sleeve.csv 1행: VDplus 55%, SYN05 20%, 1662a 25%  SR=1.1851
  # SYN05가 VDplus 안에 포함된 구조이므로, 현재 의사결정 기준:
  # 기존 = VDplus 75% + Q07 25% (SYN05 없는 단순화 버전 비교)
  list(name = "A: VDplus 60% + Q07 15% + M3 25%",
       wvdp = 0.60, wq07 = 0.15, w930 = 0.25),
  list(name = "B: VDplus 55% + Q07 15% + M3 15% + (MLRA 15%→보수현금)",
       wvdp = 0.55, wq07 = 0.15, w930 = 0.30),  # MLRA 자리 M3에 합산
  list(name = "C: VDplus 70% + Q07 10% + M3 20%",
       wvdp = 0.70, wq07 = 0.10, w930 = 0.20),
  list(name = "D: VDplus 65% + Q07 10% + M3 25%",
       wvdp = 0.65, wq07 = 0.10, w930 = 0.25),
  list(name = "E: VDplus 50% + Q07 25% + M3 25%",
       wvdp = 0.50, wq07 = 0.25, w930 = 0.25),
  # 참조: 현재 2-sleeve 최적 (VDplus 75% + Q07 25%)
  list(name = "REF: VDplus 75% + Q07 25% (현 2-sleeve)",
       wvdp = 0.75, wq07 = 0.25, w930 = 0.00)
)

results_list <- lapply(scenarios, function(sc) {
  rets <- with(mon4, ret_vdp * sc$wvdp + ret_q07 * sc$wq07 + ret_930 * sc$w930)
  p <- calc_perf(rets, sc$name)
  as.data.table(p)
})
results_dt <- rbindlist(results_list)

cat("\n=== 시나리오별 성과 ===\n")
print(results_dt)

# ===================================================================
# 6. 한계기여 분석 (STR_930 M3 추가 효과)
# ===================================================================
cat("\n[5] 한계기여 분석...\n")

# 기준: VDplus 75% + Q07 25% (M3 없음)
base_rets <- mon4$ret_vdp * 0.75 + mon4$ret_q07 * 0.25
base_perf <- calc_perf(base_rets, "Base (VDplus75+Q0725)")

# 최적 4-sleeve (시나리오 A)
optA_rets <- mon4$ret_vdp * 0.60 + mon4$ret_q07 * 0.15 + mon4$ret_930 * 0.25
optA_perf <- calc_perf(optA_rets, "A: VDplus60+Q0715+M325")

# 시나리오 D
optD_rets <- mon4$ret_vdp * 0.65 + mon4$ret_q07 * 0.10 + mon4$ret_930 * 0.25
optD_perf <- calc_perf(optD_rets, "D: VDplus65+Q0710+M325")

cat("\n=== 한계기여 (기준 대비) ===\n")
cat(sprintf("%-35s  CAGR  AnnVol    SR     MDD  Calmar\n", "Scenario"))
cat(strrep("-", 85), "\n")
for (p in list(base_perf, optA_perf, optD_perf)) {
  cat(sprintf("%-35s %5.2f%%  %5.2f%%  %5.3f  %5.2f%%  %5.3f\n",
      substr(p$Label, 1, 35),
      p$CAGR, p$AnnVol, p$SR, p$MDD, p$Calmar))
}
cat(strrep("-", 85), "\n")

delta_A <- optA_perf$SR - base_perf$SR
delta_A_mdd <- optA_perf$MDD - base_perf$MDD
delta_A_cagr <- optA_perf$CAGR - base_perf$CAGR
cat(sprintf("\n[시나리오 A 한계기여]\n  SR 개선: %+.3f | CAGR 개선: %+.2f%% | MDD 개선: %+.2f%%\n",
    delta_A, delta_A_cagr, delta_A_mdd))

# ===================================================================
# 7. 상관관계 분석
# ===================================================================
cat("\n[6] 전략간 상관관계...\n")
cm <- corr_mat(mon4)
cat("상관계수 행렬 (월별 수익률 기준):\n")
print(cm)

# M3 vs 다른 전략 개별 상관
cat(sprintf("\n  STR_930 M3 vs VDplus: %.3f\n", cor(mon4$ret_930, mon4$ret_vdp)))
cat(sprintf("  STR_930 M3 vs Q07:   %.3f\n", cor(mon4$ret_930, mon4$ret_q07)))

# ===================================================================
# 8. 연별 수익률 비교 (최근 5년)
# ===================================================================
cat("\n[7] 연별 수익률 비교 (최근 5년)...\n")
base_yr <- annual_ret(base_rets, mon4$Date)
optA_yr <- annual_ret(optA_rets, mon4$Date)
optD_yr <- annual_ret(optD_rets, mon4$Date)
m3_yr   <- annual_ret(mon4$ret_930, mon4$Date)

recent_yrs <- tail(sort(unique(base_yr$yr)), 6)
cmp <- merge(
  base_yr[yr %in% recent_yrs],
  optA_yr[yr %in% recent_yrs],
  by = "yr", suffixes = c("_base", "_A")
)
cmp <- merge(cmp, optD_yr[yr %in% recent_yrs], by = "yr")
cmp <- merge(cmp, m3_yr[yr %in% recent_yrs], by = "yr", suffixes = c("_D", "_M3"))
setnames(cmp, c("yr", "Base(VDP75+Q25)", "Scen_A", "Scen_D", "STR930_M3"))
cat("\n연별 수익률 (%):\n")
print(cmp)

# ===================================================================
# 9. 최적 배분 그리드 서치 (VDplus + Q07 + M3)
# ===================================================================
cat("\n[8] 그리드 서치 (w_vdp + w_q07 + w_930 = 1.0)...\n")

grid <- data.table(
  expand.grid(
    w_vdp = seq(0.40, 0.75, by = 0.05),
    w_q07 = seq(0.05, 0.30, by = 0.05),
    w_930 = seq(0.10, 0.35, by = 0.05)
  )
)
grid <- grid[abs(w_vdp + w_q07 + w_930 - 1.0) < 0.001]

grid_perf <- grid[, {
  rets <- mon4$ret_vdp * w_vdp + mon4$ret_q07 * w_q07 + mon4$ret_930 * w_930
  p <- calc_perf(rets)
  .(SR = p$SR, CAGR = p$CAGR, MDD = p$MDD, Calmar = p$Calmar)
}, by = .(w_vdp, w_q07, w_930)]

# 최고 SR
top_sr <- grid_perf[order(-SR)][1:10]
cat("\nTop 10 by SR:\n")
print(top_sr)

# 최저 MDD (MDD > -25% 필터)
top_mdd <- grid_perf[MDD > -25][order(-SR)][1:5]
cat("\nTop 5 (MDD < 25%) by SR:\n")
print(top_mdd)

# ===================================================================
# 10. 결과 저장
# ===================================================================
cat("\n[9] 결과 저장...\n")
fwrite(results_dt,  file.path(OUT_DIR, "portfolio_4sleeve_scenarios.csv"))
fwrite(grid_perf,   file.path(OUT_DIR, "portfolio_4sleeve_grid.csv"))
fwrite(mon4,        file.path(OUT_DIR, "portfolio_4sleeve_monthly_rets.csv"))

# 요약 JSON
summary_obj <- list(
  run_date    = as.character(Sys.Date()),
  period      = list(start = as.character(min(mon4$Date)), end = as.character(max(mon4$Date))),
  n_months    = nrow(mon4),
  base_2sleeve = base_perf,
  best_4sleeve = optA_perf,
  delta_SR    = delta_A,
  delta_CAGR  = delta_A_cagr,
  delta_MDD   = delta_A_mdd,
  correlation = list(
    M3_vs_VDplus = round(cor(mon4$ret_930, mon4$ret_vdp), 3),
    M3_vs_Q07    = round(cor(mon4$ret_930, mon4$ret_q07), 3),
    VDplus_vs_Q07 = round(cor(mon4$ret_vdp, mon4$ret_q07), 3)
  ),
  top_grid = top_sr[1:3]
)
jsonlite::write_json(summary_obj, file.path(OUT_DIR, "portfolio_4sleeve_summary.json"),
                     auto_unbox = TRUE, pretty = TRUE)

cat("\n=== 완료 ===\n")
cat(sprintf("  - portfolio_4sleeve_scenarios.csv\n"))
cat(sprintf("  - portfolio_4sleeve_grid.csv\n"))
cat(sprintf("  - portfolio_4sleeve_summary.json\n"))
