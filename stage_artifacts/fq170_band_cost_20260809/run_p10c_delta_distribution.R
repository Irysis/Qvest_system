## P10c — 순서를 못 맞혀도 쓸 수 있는가: 52 base 의 밴드 Δ 분포와 하방
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P9c: slope 는 계열 간 **순서**를 못 맞힌다(교차 -0.108/+0.081). 그러나 51/52 에서 Δ>0.
##  ⇒ 순서 예측과 **독립적인** 질문: 밴드를 사전판정 없이 **기본값으로 켤 수 있는가**.
##  측정: swap_d(연율 %p)의 분포 — 중앙값·사분위·하위 10%·최악, 그리고 **계열별 최악**.
##   Y1_SAFE_DEFAULT : 하위10% >= 0 ∧ 최악 > -1.0%p  → 순서 몰라도 켤 만하다
##   Y2_MOSTLY_SAFE  : 하위10% >= 0 이나 최악 <= -1.0%p → 켜되 계열 예외 목록 필요
##   Y3_NOT_DEFAULT  : 하위10% < 0 → 사전판정 없이는 못 켠다
##  ⚠swap_d 는 **패널 산술**(gross, 선택집합 초과수익 차)이지 PORT_t 가 아니다.
##    P8a 에서 부호가 PORT_t Δ 와 3/3 일치했으나 그건 n=3 이다 — **크기 환산 금지**.
##  ★성과·자본 주장 없음. 새 측정 아님(P9c 산출물의 분포 요약).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
R <- fread(file.path(OUT, "p9c_bases.csv"))
cat(sprintf("[입력 실측] base %d · 계열 %d\n", nrow(R), uniqueN(R$fam)))
d <- R$swap_all
qs <- quantile(d, c(0, 0.10, 0.25, 0.50, 0.75, 0.90, 1), na.rm = TRUE)
cat("\n=== 밴드 Δ (swap_d, 연율 %p) 분포 ===\n")
print(round(qs, 3))
cat(sprintf("\n평균 %.3f · 중앙 %.3f · sd %.3f · 양수 %d/%d (%.1f%%)\n",
            mean(d), median(d), sd(d), sum(d > 0), length(d), 100*mean(d > 0)))
## 홀/짝 분할에서도 부호가 유지되는 base 비율 — 우연 양수 배제
both_pos <- sum(R$swap_odd > 0 & R$swap_evn > 0)
cat(sprintf("홀·짝 **양쪽 모두** 양수: %d/%d (%.1f%%) ← 우연 양수 배제\n",
            both_pos, nrow(R), 100*both_pos/nrow(R)))
cat("\n=== 계열별 최악 / 중앙 ===\n")
BF <- R[, .(n=.N, worst=round(min(swap_all),3), med=round(median(swap_all),3),
            both_pos=sum(swap_odd>0 & swap_evn>0)), by=fam][order(worst)]
print(BF)
cat("\n=== 최악 5 base ===\n")
print(R[order(swap_all)][1:5, .(base, fam, swap_all=round(swap_all,3),
                                odd=round(swap_odd,3), evn=round(swap_evn,3))])
p10 <- as.numeric(qs[2]); worst <- as.numeric(qs[1])
verdict <- if (p10 >= 0 && worst > -1.0) "Y1_SAFE_DEFAULT" else
           if (p10 >= 0) "Y2_MOSTLY_SAFE" else "Y3_NOT_DEFAULT"
cat(sprintf("\n하위10%% %.3f · 최악 %.3f\n판정: %s\n", p10, worst, verdict))
cat("⚠swap_d = 패널 산술(gross). PORT_t 로 크기 환산 금지 — 부호 일치는 n=3 근거뿐\n")
write_json(list(verdict=verdict, n_base=nrow(R), quantiles=as.list(round(qs,4)),
                mean=mean(d), median=median(d), sd=sd(d),
                n_positive=sum(d>0), n_both_split_positive=both_pos,
                by_family=BF), file.path(OUT,"p10c_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
