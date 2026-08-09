## w5 — ★역설 확인: mega_spread<=0(대형 패배) 월에 소형편향 PG2 의 active 가 왜 더 낮은가
## 관측(y2): PG2 active ON 0.0130 vs OFF 0.0278. PG2 = top-25 EW(소형편향), 벤치 = KOSPI200(cap-w).
##   대형이 지는 달이면 소형편향 포트가 cap-w 벤치를 **더** 이겨야 한다. 관측은 반대다.
## ⇒ 후보: ①정렬(+2) 오류로 ON 라벨이 실제 대형-패배 월과 어긋남 ②t-1 FROZEN 이라 라벨이 선행 신호임
##          ③mega_spread 정의가 내 해석과 다름
## ★PG2 타임라인에서 **직접** 대형-소형 스프레드를 만들어 교차 확인한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[w5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
M <- readRDS(file.path(OUT,"mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]; SZ <- as.data.table(M$size_dt)
say("=== 1. PG2 타임라인에서 대형-소형 스프레드 직접 산출 ===")
J <- merge(ret[, .(Date, Ticker, Ret_1m)], SZ[, .(Date, Ticker, Size)], by=c("Date","Ticker"))
SP <- J[, { o <- order(-Size); t10 <- head(o, 10)
            .(ms = mean(Ret_1m[t10], na.rm=TRUE) - median(Ret_1m, na.rm=TRUE),
              n = .N) }, by = Date]
SP[, m := mi(Date) + 2L]          # 후보 패널 규약(+2)
SP2 <- copy(SP)[, m := mi(Date)]  # 정렬 없음
say("  스프레드 %d개월 · 중앙 %+.4f · sd %.4f · 음수 비율 %.1f%%",
    nrow(SP), median(SP$ms), sd(SP$ms), 100*mean(SP$ms <= 0))

say("=== 2. ★정렬별로 PG2 active 가 대형-패배 월에 높은가 (기대: 높다) ===")
for (nm in c("+2 정렬","무정렬")) {
  S <- if (nm == "+2 정렬") SP else SP2
  Z <- merge(inc[, .(m, act = active)], S[, .(m, ms)], by="m")
  Z[, lose := ms <= 0]
  Z[, lose_lag := shift(ms, 1L) <= 0]         # FQ-138 은 t-1 FROZEN
  say("  [%s] n=%d", nm, nrow(Z))
  say("    동시 대형패배월(ms<=0)  : PG2 active 평균 %+.5f (n %d) vs 그 외 %+.5f (n %d) · 차 %+.5f",
      mean(Z[lose %in% TRUE, act]), sum(Z$lose, na.rm=TRUE),
      mean(Z[lose %in% FALSE, act]), sum(!Z$lose, na.rm=TRUE),
      mean(Z[lose %in% TRUE, act]) - mean(Z[lose %in% FALSE, act]))
  say("    t-1 대형패배월(FROZEN)  : PG2 active 평균 %+.5f (n %d) vs 그 외 %+.5f (n %d) · 차 %+.5f",
      mean(Z[lose_lag %in% TRUE, act], na.rm=TRUE), sum(Z$lose_lag, na.rm=TRUE),
      mean(Z[lose_lag %in% FALSE, act], na.rm=TRUE), sum(!Z$lose_lag, na.rm=TRUE),
      mean(Z[lose_lag %in% TRUE, act], na.rm=TRUE) - mean(Z[lose_lag %in% FALSE, act], na.rm=TRUE))
  say("    상관 cor(ms, PG2 active) = %+.3f · cor(ms_{t-1}, active_t) = %+.3f",
      cor(Z$ms, Z$act, use="complete.obs"),
      cor(shift(Z$ms,1L), Z$act, use="complete.obs"))
}
say("  ★기대: 동시 대형패배월에 PG2 active 가 **높아야** 한다(소형편향 vs cap-w 벤치).")
say("     동시 상관이 음수면 정합, 양수면 내 해석이 틀린 것.")

say("=== 3. FQ-191 라벨과 직접 산출 라벨의 일치 ===")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
CK <- merge(LB, SP[, .(m, ms)], by="m")
CK[, own := ms <= 0]
say("  겹침 %d개월 · FQ191 ON %d · 직접산출 ms<=0 %d · **일치 %.1f%%**",
    nrow(CK), sum(CK$on), sum(CK$own, na.rm=TRUE), 100*mean(CK$on == CK$own, na.rm=TRUE))
CK[, own_lag := shift(ms, 1L) <= 0]
say("  t-1 판본과 일치 **%.1f%%**", 100*mean(CK$on == CK$own_lag, na.rm=TRUE))
say("  ⇒ FQ-191 라벨은 t-1 FROZEN 이므로 t-1 판본과 높게 일치해야 정상")

say("=== 4. ★판정 ===")
Z <- merge(inc[, .(m, act = active)], SP[, .(m, ms)], by="m")
c0 <- cor(Z$ms, Z$act, use="complete.obs")
say("  동시 cor(대형-소형 스프레드, PG2 active) = **%+.3f**", c0)
say("  ⇒ %s", if (c0 < -0.2)
  "★정합 — 대형이 질수록 PG2 가 벤치를 더 이긴다. 그러면 y2 의 'ON 월 active 낮음' 은 **t-1 라벨의 선행성** 때문이다" else
  if (c0 > 0.2) "★★내 해석이 틀렸다 — 대형이 질수록 PG2 active 가 **낮다**. 소형편향 가정을 재검토해야 한다" else
  "★관계가 약하다 — PG2 active 는 대형-소형 축과 크게 연동되지 않는다")
say("  ★이것이 중요한 이유: ON 월의 상관 하락(전 재료 공통)이 **무엇의 결과인지**를 정하는 전제다.")
saveRDS(list(SP=SP, Z=Z, CK=CK), file.path(OUT,"w5.rds"))
say("=== w5 완료 ===")
