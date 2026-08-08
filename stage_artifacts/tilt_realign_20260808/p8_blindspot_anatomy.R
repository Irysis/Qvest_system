# p8_blindspot_anatomy.R — 라벨 lane L3: 사각지대 위기월의 성질 해부 (예측 시도 前)
# 질문: NORMAL/BULL 라벨을 달고 최악 10분위에 들어간 8개월은 **시장 급락**인가 **전략 고유 손실**인가?
#   시장 급락 → 국면 신호로 잡을 여지 있음(L1/L2 유효)
#   전략 고유 → 어떤 시장상태 신호로도 원리적으로 못 잡음(L1/L2 무의미, 포지션 레벨로 재라우팅)
# 9종 신호 실패의 원인이 '신호가 나빠서'인지 '표적이 국면이 아니어서'인지를 가른다.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
setorder(R, decision_date)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)][order(Date)]

## 홀딩월 벤치수익 = (decision_date, eval_date] 복리 — 슬리브 수익창과 동일 정렬
R[, bm_ret := sapply(seq_len(.N), function(i) {
  w <- bm[Date > R$decision_date[i] & Date <= R$eval_date[i]]
  if (!nrow(w)) NA_real_ else prod(1 + w$BM_Ret) - 1 })]
R[, active := gA - bm_ret]
R[, thr := sapply(seq_len(.N), function(i) if (i <= 36L) NA_real_ else quantile(gA[1:(i-1)], 0.10, names=FALSE))]
R[, crisis := is.finite(thr) & gA <= thr]
E <- R[is.finite(thr) & is.finite(bm_ret)]
E[, caught := regime %in% c("CRISIS","CAUTION")]
E[, grp := fifelse(!crisis, "정상월", fifelse(caught, "포착 위기월", "★사각 위기월"))]

cat(sprintf("[표본] %d개월 | 위기월 %d (포착 %d · 사각 %d)\n",
            nrow(E), sum(E$crisis), sum(E$crisis & E$caught), sum(E$crisis & !E$caught)))

cat("\n===== 그룹별 성질 =====\n")
print(E[, .(개월=.N,
            sleeve_gross=sprintf("%+.2f%%", 100*mean(gA)),
            benchmark=sprintf("%+.2f%%", 100*mean(bm_ret)),
            active=sprintf("%+.2f%%", 100*mean(active)),
            `벤치도_음수_비율`=sprintf("%.0f%%", 100*mean(bm_ret < 0)),
            `active_음수_비율`=sprintf("%.0f%%", 100*mean(active < 0))), by=grp][order(-개월)])

cat("\n===== 사각 위기월 개별 =====\n")
print(E[crisis & !caught, .(ym=format(eval_date,"%Y-%m"), regime,
        sleeve=sprintf("%+.2f%%",100*gA), bench=sprintf("%+.2f%%",100*bm_ret),
        active=sprintf("%+.2f%%",100*active),
        유형=fifelse(bm_ret <= -0.05, "시장급락", fifelse(active <= -0.05, "전략고유", "혼합")))][order(ym)])

cat("\n===== 포착 위기월 개별 (대조군) =====\n")
print(E[crisis & caught, .(ym=format(eval_date,"%Y-%m"), regime,
        sleeve=sprintf("%+.2f%%",100*gA), bench=sprintf("%+.2f%%",100*bm_ret),
        active=sprintf("%+.2f%%",100*active),
        유형=fifelse(bm_ret <= -0.05, "시장급락", fifelse(active <= -0.05, "전략고유", "혼합")))][order(ym)])

bl <- E[crisis & !caught]; ct <- E[crisis & caught]
cat(sprintf("\n[판정] 사각 위기월 벤치 평균 %+.2f%% vs 포착 위기월 %+.2f%% | 사각의 시장급락(벤치≤-5%%) 비율 %.0f%% vs 포착 %.0f%%\n",
            100*mean(bl$bm_ret), 100*mean(ct$bm_ret), 100*mean(bl$bm_ret <= -0.05), 100*mean(ct$bm_ret <= -0.05)))
cat(sprintf("[분해] 사각월 손실의 시장성분 %.0f%% / 전략성분 %.0f%%  (포착월: 시장 %.0f%% / 전략 %.0f%%)\n",
            100*mean(bl$bm_ret)/mean(bl$gA), 100*mean(bl$active)/mean(bl$gA),
            100*mean(ct$bm_ret)/mean(ct$gA), 100*mean(ct$active)/mean(ct$gA)))
tt <- t.test(bl$bm_ret, ct$bm_ret)
cat(sprintf("[검정] 사각 vs 포착 벤치수익 차이: t=%.3f p=%.4f (사각이 더 얕은 하락인가)\n", tt$statistic, tt$p.value))
cat(sprintf("[난이도] 정상월 중 벤치 음수 비율 %.0f%% — 사각월 평균 벤치 %.2f%% 수준의 하락은 정상월에도 흔해 판별이 어렵다\n",
            100*mean(E[crisis == FALSE, bm_ret] < 0), 100*mean(bl$bm_ret)))
nm <- E[crisis == FALSE & bm_ret < 0]
cat(sprintf("           정상월 중 벤치 ≤ -5%% 인 달 %d개(전체 정상월의 %.0f%%) — 이들이 위기월과 섞여 오탐 원천\n",
            sum(E[crisis == FALSE, bm_ret] <= -0.05), 100*mean(E[crisis == FALSE, bm_ret] <= -0.05)))
fwrite(E[crisis == TRUE, .(ym=format(eval_date,"%Y-%m"), regime, caught, gA, bm_ret, active)],
       "stage_artifacts/tilt_realign_20260808/p8_blindspot_anatomy.csv")
cat("[saved] p8_blindspot_anatomy.csv\n")
