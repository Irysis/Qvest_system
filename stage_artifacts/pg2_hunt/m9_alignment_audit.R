## m9 — ★정렬 감사: 파킹 구성에 쓴 benchmark_ret 이 슬리브 r 과 **같은 달인가**
## 의심 근거(m8): 무작위 라벨의 실현 β = **0.636** ≈ OFF 비율 **0.644**.
##   정렬돼 있다면 β ~ 0.356*0.92 + 0.644*1.0 = **0.97** 이어야 한다.
##   0.636 은 "ON 월의 r 이 bm 과 무상관 → OFF 월(비율 0.644)만 β=1 기여" 의 정확한 지문이다.
## ★기전 가설: bm_load_incumbent 의 정렬 오프셋(+2)은 bm_delta_ir **내부**에서만 적용된다.
##   그런데 나는 merge(inc[,.(m,benchmark_ret)], S[,.(m,r)], by="m") 로 **직접** 붙여 파킹을 만들었다
##   ⇒ 파킹의 OFF 월 대체값이 **2개월 어긋난 벤치**일 수 있다. m1/m2/m7/m8 및 어제 n1/o1/p1 전부 영향.
## ★판정: r 과 benchmark_ret 의 상관을 오프셋 -4..+4 로 훑어 **최대 지점**을 찾는다. 0 이면 무결.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m9] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
TG <- fread(file.path(OUT,"s8_parked.csv"))$id

say("=== ① inc 자체 무결성 (PG2 자기 수익 vs 자기 벤치) ===")
say("  cor(ret_net, benchmark_ret) = **%.4f** · β = %.4f · n %d",
    cor(inc$ret_net, inc$benchmark_ret), unname(coef(lm(ret_net ~ benchmark_ret, inc))[2]), nrow(inc))
say("  ⇒ inc 내부는 %s (long-only 북이면 0.9 근방이 정상)",
    if (cor(inc$ret_net, inc$benchmark_ret) > 0.8) "**정렬 정상**" else "★비정상")

say("=== ② 슬리브 r 과 inc$benchmark_ret 의 오프셋 스캔 (핵심) ===")
say("  %-28s %s", "strategy", paste(sprintf("%7s", sprintf("%+d", -3:3)), collapse=""))
peaks <- integer(0)
for (nm in TG) { j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  cs <- vapply(-3:3, function(k) {
    Z <- merge(inc[, .(m, bm = benchmark_ret)], S[, .(m = m + k, r)], by = "m")
    if (nrow(Z) < 40) return(NA_real_); suppressWarnings(cor(Z$r, Z$bm, use="complete.obs")) }, numeric(1))
  pk <- (-3:3)[which.max(cs)]; peaks <- c(peaks, pk)
  say("  %-28s %s  ← 최대 %+d", substr(nm,1,28), paste(sprintf("%7.3f", cs), collapse=""), pk) }
say("  ★오프셋 최댓값 분포: %s", paste(sprintf("%+d:%d회", as.integer(names(table(peaks))), table(peaks)), collapse=" · "))
say("  ⇒ **%s**", if (all(peaks == 0L)) "오프셋 0 = 파킹 구성 무결 (β 0.636 은 다른 원인)" else
    sprintf("★오프셋 %+d 지배 = 파킹의 OFF 월 벤치가 어긋나 있었다", as.integer(names(sort(table(peaks), decreasing=TRUE))[1])))

say("=== ③ β 0.636 의 대안 설명 검정 — 슬리브가 원래 저베타인가 ===")
for (nm in TG[1:4]) { j <- which(INV$names == nm)[1]
  Z <- merge(inc[, .(m, bm = benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")
  say("  %-28s cor %.3f · β(무처리) **%.3f** · sd(r) %.4f · sd(bm) %.4f",
      substr(nm,1,28), cor(Z$r, Z$bm), unname(coef(lm(r ~ bm, Z))[2]), sd(Z$r), sd(Z$bm)) }
say("  ⇒ 무처리 β 가 이미 0.9 근방이면 파킹 β 0.26 은 **선택 효과**, 0.3 근방이면 **원래 저베타**")

say("=== ④ 산술 확인 — 무작위 라벨 β 의 이론값 ===")
j <- which(INV$names == TG[1])[1]
Z <- merge(inc[, .(m, bm = benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")
b0 <- unname(coef(lm(r ~ bm, Z))[2]); p <- 0.3562
say("  무처리 β=%.3f · ON비율 %.3f ⇒ 무작위 파킹 β 이론 = %.3f*%.3f + %.3f*1 = **%.3f**",
    b0, p, p, b0, 1-p, p*b0 + (1-p))
say("  실측 무작위 β 중앙 = **0.636** ⇒ %s", if (abs(p*b0 + (1-p) - 0.636) < 0.08) "이론과 정합" else "★이론과 불일치 = 미해명")
say("=== m9 완료 ===")
