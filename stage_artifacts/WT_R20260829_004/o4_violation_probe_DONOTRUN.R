# 위반 주입 probe — 실행 금지(계기 발화 실증 전용).
mu <- mean(returns$Ret)                 # C1: full-sample 통계
sd_all <- sd(prices$Close)              # C1
z <- (x - mean(x)) / sd(x)              # C1 full-sample z
w <- weights[Date == today]             # C2 same-day
sig <- factor_scores[Date == rebal_date]  # C2
dd_now <- dd_pct[n]                     # C9 동일자 낙폭
liq <- adv[Date == sig_date]            # C10 당일 유동성
