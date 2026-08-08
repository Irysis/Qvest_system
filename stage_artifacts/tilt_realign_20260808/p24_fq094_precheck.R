# p24_fq094_precheck.R — FQ-094 착수 전 사전 확인 (owner=Q-Lead, 지시 불요)
# 제안: T_RetAutoCorr_12M **역방향** — lag-1 자기상관이 낮은/음수인 종목(평균회귀) long.
#   정방향은 FMB t=2.50* 인데 PORT_t −0.295 로 전이 차단(DIST-AR-003).
# 사전 확인 3축 (전제가 참인가):
#   ①역방향 rank-IC 가 실제로 양수인가 (정방향의 단순 부호 반전이 아닐 수 있음)
#   ②wall_check 우려: low-autocorr = **고변동성 종목 과다표현**인가 (교락 사전 확인)
#   ③cap-tier 국소화 벽 — MEGA/MID 어디에 사는 신호인가
# ★PIT: 자기상관은 decision_date 이전 12개월만. 수익은 익월.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret","Size","Close","Vol")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, `:=`(ymd = as.Date(paste0(format(Date,"%Y-%m"),"-01")), TV = Close*Vol)]
MO <- raw[, .(ret_m = prod(1+Ret)-1, vol_m = sd(Ret, na.rm=TRUE), size = last(Size[is.finite(Size)]),
              adv = mean(TV, na.rm=TRUE), nd = .N), by=.(Ticker, ymd)][nd >= 10 & is.finite(ret_m)]
setorder(MO, Ticker, ymd)
MO[, mi := as.integer(format(ymd,"%Y"))*12L + as.integer(format(ymd,"%m"))]
cat(sprintf("[월 패널] %s행 · %d종목 · %s~%s\n", format(nrow(MO), big.mark=","), uniqueN(MO$Ticker),
            min(MO$ymd), max(MO$ymd)))

## 12개월 창 lag-1 자기상관 (과거만)
ac12 <- function(x) { if (length(x) < 12 || sd(x, na.rm=TRUE) == 0) return(NA_real_)
  suppressWarnings(cor(x[-length(x)], x[-1], use="complete.obs")) }
MO[, autocorr := frollapply(ret_m, 12, ac12, align="right", fill=NA_real_), by=Ticker]
MO[, ac_lag := shift(autocorr, 1), by=Ticker]      # ★결정 시점엔 전월까지의 창만 사용
MO[, fwd := shift(ret_m, -1), by=Ticker]           # 익월 수익
E <- MO[is.finite(ac_lag) & is.finite(fwd) & is.finite(adv) & adv >= 2e8]
cat(sprintf("[유효] %s행 (유동성 2e8 필터 후) · %d개월\n", format(nrow(E), big.mark=","), uniqueN(E$mi)))

## ① 역방향 rank-IC (낮은 autocorr = long → 부호 반전한 신호)
E[, sig_rev := -ac_lag]
IC <- E[, .(ic = if (.N >= 30) suppressWarnings(cor(frank(sig_rev), frank(fwd), method="spearman")) else NA_real_,
            n = .N), by=mi][is.finite(ic)]
m <- mean(IC$ic); s <- sd(IC$ic); tstat <- m/(s/sqrt(nrow(IC)))
cat(sprintf("\n[① 역방향 rank-IC] %d개월 | mean %.4f · sd %.4f · **t = %.2f** | IC>0 비율 %.1f%%\n",
            nrow(IC), m, s, tstat, 100*mean(IC$ic > 0)))

## ② 교락: low-autocorr 가 고변동성 종목인가
E[, ac_q := cut(frank(ac_lag)/.N, c(0,0.2,0.8,1), labels=c("최저20","중간","최고20")), by=mi]
cf <- E[!is.na(ac_q), .(n=.N, 변동성=round(mean(vol_m, na.rm=TRUE),4),
                        로그시총=round(mean(log(pmax(size,1)), na.rm=TRUE),2),
                        익월수익=round(100*mean(fwd),2)), by=ac_q][order(ac_q)]
cat("\n[② 교락 확인 — autocorr 분위별]\n"); print(cf)
lo <- E[ac_q=="최저20"]; hi <- E[ac_q=="최고20"]
cat(sprintf("  최저20 vs 최고20: 변동성 %.4f vs %.4f (t=%.2f) | 익월수익 %+.2f%% vs %+.2f%% (t=%.2f, p=%.4f)\n",
  mean(lo$vol_m,na.rm=TRUE), mean(hi$vol_m,na.rm=TRUE),
  t.test(lo$vol_m, hi$vol_m)$statistic, 100*mean(lo$fwd), 100*mean(hi$fwd),
  t.test(lo$fwd, hi$fwd)$statistic, t.test(lo$fwd, hi$fwd)$p.value))

## ③ cap-tier 국소화
E[, cap := cut(frank(-size)/.N, c(0,0.1,0.5,1), labels=c("MEGA","MID","SMALL")), by=mi]
ct <- E[!is.na(cap), .(ic = suppressWarnings(cor(frank(sig_rev), frank(fwd), method="spearman")), n=.N), by=.(cap, mi)]
ct2 <- ct[is.finite(ic), .(개월=.N, mean_IC=round(mean(ic),4), t=round(mean(ic)/(sd(ic)/sqrt(.N)),2)), by=cap][order(cap)]
cat("\n[③ cap-tier 분해]\n"); print(ct2)
cat(sprintf("\n[사전 확인 판정] 역방향 IC t=%.2f · 교락(변동성 격차) %s · cap 국소화 %s → %s\n",
  tstat, ifelse(abs(mean(lo$vol_m,na.rm=TRUE)-mean(hi$vol_m,na.rm=TRUE)) > 0.005, "있음", "경미"),
  ifelse(max(abs(ct2$t)) > 2 && min(abs(ct2$t)) < 1, "특정 tier 편중", "고른 편"),
  ifelse(abs(tstat) >= 2, "라운드 착수 가치 있음", "★전제 약함 — 착수 EV 낮음")))
fwrite(ct2, "stage_artifacts/tilt_realign_20260808/p24_fq094_captier.csv")
