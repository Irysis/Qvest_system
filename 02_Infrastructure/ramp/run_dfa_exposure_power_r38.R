## run_dfa_exposure_power_r38.R — R38: '노출축은 과적합 취약' 진단을 검정력으로 확정/기각
## 질문: 위기 에피소드가 몇 개뿐인 표본에서 16종 신호 중 최선을 고르면, 그 최선이 우연으로 나올 수 있는가.
## 방법: **순환 시프트 순열검정** — 각 신호의 시간 구조(발화 런 길이)는 보존하고 시장과의 정렬만 파괴한다.
##       귀무 = "이 신호는 위기와 무관하나 같은 발화 패턴을 갖는다".
##       비교 대상은 단일 신호가 아니라 **16종 중 최댓값**(선정 절차 전체의 귀무분포).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MDD  <- function(r){ n <- cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
BPS <- 15

Z <- readRDS(".cache/_dfa_r29.rds"); mon <- Z$mon; PR <- Z$PR; k <- Z$k
NM <- nrow(mon); MKT <- mon$Market; ym <- mon$ym
IS <- ym <= "2015-06"; kIS <- k[IS[k]]

cat("=== [1] 위기 에피소드 census — 유효 표본 단위는 '월' 이 아니라 '에피소드' 다 ===\n")
nav <- cumprod(1 + MKT); dd <- nav/cummax(nav) - 1
epi <- function(thr){
  inx <- dd <= thr; runs <- rle(inx)
  n <- sum(runs$values); lens <- runs$lengths[runs$values]
  list(n = n, months = sum(lens), med_len = if (n) median(lens) else NA) }
for (th in c(-0.10, -0.15, -0.20, -0.30)) {
  e <- epi(th)
  cat(sprintf("  낙폭 <= %+.0f%%: 에피소드 %2d개 · 해당 월 %3d (%.1f%%) · 중앙 길이 %s개월\n",
      100*th, e$n, e$months, 100*e$months/NM, ifelse(is.na(e$med_len), "-", format(e$med_len))))
}
eIS <- { inx <- dd[IS] <= -0.20; r <- rle(inx); sum(r$values) }
cat(sprintf("  ⇒ IS 창(%d개월)의 -20%% 이상 낙폭 에피소드 = %d개. 노출 규칙 1개를 고르는 유효 표본이 이것이다.\n",
            sum(IS), eIS))

## ── 후보 신호 (R37 과 동일 16종) ──
SIG <- list()
v2 <- as.data.table(read_parquet(".cache/regime_daily_v2.parquet")); v2[, Date := as.Date(Date)]
v2[, ymm := format(Date,"%Y-%m")]
for (nm in c("MRS","n_axes_firing","VIX_z_smooth","FinStress_z_smooth","KRW_z_smooth",
             "NFCI_z_smooth","Claims_z_smooth","Sentiment_z_smooth","TS_z_smooth"))
  if (nm %in% names(v2)) SIG[[nm]] <- v2[, .(s = last(get(nm))), by = ymm]
pb <- as.data.table(read_parquet("06_Registry/regime_published/regime_signal_daily_published.parquet"))
pb[, Date := as.Date(Date)]; pb[, ymm := format(Date,"%Y-%m")]
for (nm in c("MSM_Crisis_Prob","FRED_MRS","Regime_Score","Regime_Score_smooth","KTRI_Score","Cash_Pct"))
  if (nm %in% names(pb)) SIG[[nm]] <- pb[, .(s = last(get(nm))), by = ymm]
SIG[["MKT_MOM3M_control"]] <- data.table(ymm = ym,
  s = sapply(seq_len(NM), function(m) if (m < 3) NA_real_ else -(prod(1+MKT[(m-2):m])-1)))

caus_flag <- function(s, q = 0.80, burn = 24L){
  n <- length(s); f <- rep(FALSE, n); acc <- numeric(0)
  for (i in seq_len(n)) {
    if (i > burn && is.finite(s[i])) { th <- quantile(acc, q, na.rm=TRUE); if (is.finite(th)) f[i] <- s[i] >= th }
    if (is.finite(s[i])) acc <- c(acc, s[i]) }
  f }
apply_e <- function(e){ r <- PR[,"T3"]; out <- rep(NA_real_, NM); ep <- 1
  for (m in seq_len(NM)) { if (!is.finite(r[m])) next
    out[m] <- e[m]*r[m] - (BPS/1e4)*abs(e[m]-ep); ep <- e[m] }; out }
cal_IS <- function(x){ v <- x[kIS]; v <- v[is.finite(v)]
  if (length(v) < 24) return(NA_real_); CAGR(v)/abs(MDD(v)) }

## 실측 발화 벡터 (결정시점 lag 1 반영)
FL <- list()
for (nm in names(SIG)) {
  d <- SIG[[nm]]; s <- d$s[match(ym, d$ymm)]; s <- c(NA_real_, s)[seq_len(NM)]
  FL[[nm]] <- caus_flag(s)
}
base_IS <- cal_IS(PR[,"T3"])
obs <- sapply(names(FL), function(nm) cal_IS(apply_e(ifelse(FL[[nm]], 0, 1))))
cat(sprintf("\n=== [2] 관측 — base IS calmar %.4f | 16종 최댓값 %.4f (%s) ===\n",
            base_IS, max(obs, na.rm=TRUE), names(which.max(obs))))

cat("\n=== [3] 순환 시프트 귀무분포 (시간 구조 보존, 시장 정렬 파괴) ===\n")
set.seed(20260822); NREP <- 400L
shift_cal <- function(fl, off){ e <- ifelse(fl[((seq_len(NM) - 1 + off) %% NM) + 1], 0, 1); cal_IS(apply_e(e)) }
null_max <- numeric(NREP); null_all <- matrix(NA_real_, NREP, length(FL))
offs <- sample(12:(NM-12), NREP*length(FL), replace = TRUE); ii <- 1L
for (r in seq_len(NREP)) {
  v <- sapply(names(FL), function(nm) { o <- offs[ii]; ii <<- ii + 1L; shift_cal(FL[[nm]], o) })
  null_all[r, ] <- v; null_max[r] <- max(v, na.rm = TRUE)
}
om <- max(obs, na.rm=TRUE)
cat(sprintf("  귀무 '16종 최댓값' 분포: 중앙 %.4f · p90 %.4f · p95 %.4f · 최대 %.4f\n",
            median(null_max), quantile(null_max,0.90), quantile(null_max,0.95), max(null_max)))
cat(sprintf("  관측 최댓값 %.4f 의 p-value = P(귀무 최댓값 >= 관측) = **%.3f**\n", om, mean(null_max >= om)))
cat(sprintf("  (참고) 단일 신호 기준 귀무: 중앙 %.4f · p95 %.4f — 선정 절차를 무시하면 p 가 이만큼 낙관됨\n",
            median(null_all, na.rm=TRUE), quantile(as.numeric(null_all), 0.95, na.rm=TRUE)))
cat(sprintf("  귀무 최댓값이 base(%.4f)를 넘는 비율 = %.1f%% — 무관한 신호도 16개 중 하나는 base 를 넘는다\n",
            base_IS, 100*mean(null_max > base_IS)))

cat("\n=== [4] 판정 ===\n")
p <- mean(null_max >= om)
if (p >= 0.05) {
  cat(sprintf("  ★'노출축 과적합 취약' 진단 **지지** — 관측 최댓값이 귀무 16종-최댓값 분포 안에 있다(p=%.3f).\n", p))
  cat("    즉 R37 의 선정(Claims IS calmar 0.4806)은 우연으로 설명 가능하며, 그 OOS 붕괴는 예상된 결과다.\n")
} else {
  cat(sprintf("  ★진단 **기각** — 관측 최댓값이 귀무를 유의하게 넘는다(p=%.3f). 선정 자체는 신호를 담고 있었다.\n", p))
  cat("    그렇다면 OOS 붕괴는 과적합이 아니라 국면 변화(GFC형 위기 미재현)로 귀속해야 한다.\n")
}
saveRDS(list(obs=obs, null_max=null_max, base_IS=base_IS, p=p), ".cache/_dfa_r38.rds")
cat("\nR38_DONE\n")
