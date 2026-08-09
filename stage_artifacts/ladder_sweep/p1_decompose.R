## ★★사다리 2단(EW-basis)의 정체 분해 — 분자(mean) 이동인가 분모(se) 축소인가
## 동기: p0 에서 Δ벤치 **부호가 알파 부호를 따라간다**(양수 재료 +1.387 / 음수 재료 -0.55~-0.64).
##       상수 핸디캡이면 일률 + 이동이어야 한다. |t| 비율은 7/8 이 1.27~1.59 로 거의 일정 = **배율** 의심.
## ★이 판독이 맞으면 FQ-191 "EW 2.966 > 2.95 첫 통과" 는 신호가 아니라 **자를 바꾼 것**이다.
##   오늘 병목지도 v53/v54/v55 · FQ-178 · WT_D20260809_001 에 전파된 해석이라 즉시 확인 대상.
## t = mean(active)/se_NW3(active) 이므로 두 채널로 정확 분해:
##   Δmean 기여 = (m_e - m_c)/s_c        (분자만 바뀐 반사실)
##   Δse   기여 = m_e/s_e - m_e/s_c      (나머지)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/ladder_sweep")
say  <- function(fmt, ...) { cat(sprintf(paste0("[d] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")

W <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ169/panel.rds")))
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; bd <- as.data.table(P$bench)
liq <- as.data.table(P$liq); size_dt <- as.data.table(P$size_dt)
say("=== 입력 실측 === %d행 · %d개월", nrow(W), uniqueN(W$Date))

## NW lag-3 t (계약과 동일 정의: active = ret_net - bm 의 절편 t)
nw_t <- function(a) {
  a <- a[is.finite(a)]; if (length(a) < 12) return(c(NA, NA, NA))
  fit <- lm(a ~ 1); s <- sqrt(NeweyWest(fit, lag = 3, prewhite = FALSE, adjust = TRUE)[1,1])
  c(mean(a), s, mean(a)/s)
}

FN <- c("M26_Revenue_Mom","M01_Mom_12_1","D03_RealVol","D35_RealVol_63d",
        "D50_MaxDrawdown","D45_Downside_Dev","D41_Vol_of_Vol","D34_RealVol_21d")
FN <- intersect(FN, names(W))

say("=== ★분해: gross(0bps) 에서 cap-w 벤치 → EW-유니버스 벤치 ===")
say("  %-17s %9s %9s | %9s %9s | %8s %8s", "재료", "t_capw", "t_EW", "Δmean기여", "Δse기여", "se비율", "|t|비율")
rows <- list()
for (k in FN) {
  S <- W[!is.na(get(k)), .(Date, Ticker, score = get(k))]
  r <- suppressWarnings(canonical_screen_bt(S, ret, bd, top_n = 25L, cost_bps_oneway = 0,
        liq_dt = liq, liq_min = 2e8, run_id = "D", strategy_id = "D"))
  PR <- as.data.table(r$period_returns)[, .(date, ret_net)]
  PR <- merge(PR, bd[, .(date = Date, bm_c = BM_Ret)], by = "date")
  ## EW-유니버스 벤치 = 그 달 신호 풀의 동일가중 평균 (사다리 3단이 쓰는 정의와 동일)
  POOL <- merge(S[, .(Date, Ticker)], ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  POOL <- POOL[, .(bm_e = mean(Ret_1m, na.rm = TRUE)), by = Date]
  PR <- merge(PR, POOL[, .(date = Date, bm_e)], by = "date")
  ac <- nw_t(PR$ret_net - PR$bm_c); ae <- nw_t(PR$ret_net - PR$bm_e)
  m_c <- ac[1]; s_c <- ac[2]; m_e <- ae[1]; s_e <- ae[2]
  c_mean <- (m_e - m_c)/s_c; c_se <- m_e/s_e - m_e/s_c
  say("  %-17s %+9.3f %+9.3f | %+9.3f %+9.3f | %8.3f %8.2f",
      k, ac[3], ae[3], c_mean, c_se, s_e/s_c, abs(ae[3])/max(abs(ac[3]), 1e-9))
  rows[[length(rows)+1L]] <- data.table(factor=k, t_capw=ac[3], t_ew=ae[3],
    m_capw=m_c, m_ew=m_e, se_capw=s_c, se_ew=s_e,
    contrib_mean=c_mean, contrib_se=c_se, se_ratio=s_e/s_c)
}
R <- rbindlist(rows)

say("=== ★판정 ===")
say("  1) 평균 이동 m_e - m_c: 중앙 %+.5f/월 · sd %.5f · 부호 일치 %d/%d",
    median(R$m_ew - R$m_capw), sd(R$m_ew - R$m_capw),
    sum(sign(R$m_ew - R$m_capw) == sign(median(R$m_ew - R$m_capw))), nrow(R))
say("     → 08-08 카드('capw-EW 격차는 벤치-측 상수') 정합 여부: sd %.5f 가 작으면 상수",
    sd(R$m_ew - R$m_capw))
say("  2) se 비율 s_e/s_c: 중앙 %.3f · 범위 %.3f~%.3f (1 미만이면 EW 벤치가 se 를 줄인다)",
    median(R$se_ratio), min(R$se_ratio), max(R$se_ratio))
say("  3) 기여 크기: |Δmean기여| 중앙 %.3f vs |Δse기여| 중앙 %.3f",
    median(abs(R$contrib_mean)), median(abs(R$contrib_se)))
dom <- ifelse(median(abs(R$contrib_se)) > median(abs(R$contrib_mean)), "se 축소", "mean 이동")
say("     ⇒ ★지배 채널 = **%s**", dom)
say("  4) Δse기여의 부호가 t_capw 부호를 따라가는가(배율기 지문): 일치 %d/%d",
    sum(sign(R$contrib_se) == sign(R$t_capw)), nrow(R))
say("  5) Δmean기여는 부호 무관 일정한가: sd %.3f (작으면 진짜 상수 핸디캡 성분)",
    sd(R$contrib_mean))
say("=== ★결론 골격 ===")
say("  * Δmean 이 상수이고 Δse 가 배율이면: EW-basis 는 **핸디캡 제거 + 배율기의 합성**이다.")
say("    → 사다리 3단을 '신호가 드러난 값' 으로 읽으면 안 된다. 부호 확대분을 빼야 한다.")
say("  * FQ-191 재판정 필요 여부는 다음 스크립트(p2)에서 계약 신호로 직접 확인.")
fwrite(R, file.path(OUT, "decompose.csv")); saveRDS(R, file.path(OUT, "p1.rds"))
say("=== 완료 ===")
