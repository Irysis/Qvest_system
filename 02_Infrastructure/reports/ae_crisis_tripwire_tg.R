#!/usr/bin/env Rscript
## ae_crisis_tripwire_tg.R — AE crisis tripwire 신규 발화 텔레그램 (신규 발화 시만·dedup)
Sys.setlocale("LC_ALL", "English_United States.utf8")
suppressWarnings(suppressMessages(library(jsonlite)))
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
source("02_Infrastructure/telegram/telegram_notify.R")

j <- fromJSON("qepm/observability/ae_crisis_tripwire_latest.json", simplifyVector = FALSE)
L <- j$latest; H <- j$historical_validation; cw08 <- H$crisis_windows$`2008_GFC`; cw22 <- H$crisis_windows$`2022_bear`
chart <- file.path(root, "qepm/observability/ae_crisis_tripwire_timeline.png")

if (!isTRUE(j$alert_dedup$telegram_pending)) {
  cat("[tg] telegram_pending=FALSE — 신규 발화 없음, 발송 skip (dedup)\n"); quit(save = "no")
}
sc <- H$state_counts

res <- tg_agent_brief(
  agent = "Monitoring",
  title = sprintf("AE Crisis Tripwire 배선 — Live Regime %s", substr(L$decision_date, 1, 7)),
  as_of = j$as_of,
  sections = list(
    list(emoji = "📌", heading = "무엇을 배선했나 (급성 crisis 조기경보)", type = "bullet",
         items = c(
           "비지도 AE(오토인코더) 이상탐지 regime 신호를 monitoring crisis 조기경보 tripwire로 배선",
           "AE는 '정상' 시장 동역학만 학습 → 이탈(고 recon-error)을 급락으로 flag. 급락이 학습에 없어도 잡힘(OOD 구조적 회피)",
           "M4(BOCPD 국면 오버레이)를 *보완* — AE 발화∧M4 미발화 = M4가 놓칠 급성 OOD 경보",
           "자본/배포 신호 아님 · 자동조치 없음 · governor 무관 (도훈 판단 재료)")),
    list(emoji = "📊", heading = sprintf("현재 상태 (%s 결정월)", L$decision_date), type = "kv",
         kv = list(
           "3-state 판정"    = sprintf("%s (급성도 %s)", L$state, L$acuity),
           "AE 이탈 초과배율"= sprintf("%.2f× 임계 (seq %.2f× · pt %.2f×, 둘 다 발화)", L$exceed_max, L$exceed_seq, L$exceed_pt),
           "M4 BOCPD"        = sprintf("발화 (m4_weight_lag %.3f < 1)", L$m4_weight_lag),
           "연속 AE 발화"    = sprintf("%d개월 연속 (2025-11~%s)", L$consecutive_ae_fire_months, substr(L$decision_date,1,7)),
           "해석"            = "AE∧M4 동시발화 = 강confirm. 현 mega-cap 집중 레짐 이탈 반영 (도훈 재료)")),
    list(emoji = "🏆", heading = "왜 AE인가 — 급성 위기 포착 실측 (2008 GFC)", type = "kv",
         kv = list(
           "2008 GFC 방어"   = sprintf("AE %d/%d개월 · M4 %d/%d · (지도학습 transformer 0/9)", cw08$ae_fire, cw08$n_months, cw08$m4_fire, cw08$n_months),
           "M4 미포착 급성월"= sprintf("AE_ACUTE_ALERT %d건 = M4가 놓친 급성 OOD를 AE가 단독 포착", cw08$ae_acute_alert),
           "2022 bear"       = sprintf("AE %d vs M4 %d (전량 AE_ACUTE_ALERT — M4 완전 미발화)", cw22$ae_fire %||% 0, cw22$m4_fire %||% 0),
           "노출 중립성"     = "AE 발화율이 M4 0.126에 IS-매칭 → 타이밍 품질 격리(de-risk 예산 아님)")),
    list(emoji = "🚨", heading = sprintf("역사 3-state 분포 (%d개월 매칭)", H$n_months_matched), type = "kv",
         kv = list(
           "CALM (양자 미발화)"        = sprintf("%d개월", sc$CALM),
           "AE_ACUTE_ALERT (AE만)"     = sprintf("%d개월 = M4가 놓칠 급성 OOD", sc$AE_ACUTE_ALERT),
           "BOTH_CONFIRM (AE∧M4)"      = sprintf("%d개월 = 강confirm", sc$BOTH_CONFIRM),
           "M4_ONLY (M4만)"            = sprintf("%d개월 = M4 소관(완만 de-risk)", sc$M4_ONLY))),
    list(emoji = "➡️", heading = "규율 · 다음", type = "bullet",
         items = c(
           "임계 사전 고정(sweep 금지) · idempotent(재실행 register 0·dedup) · PIT self-check 미래참조 0",
           "산출: qepm/observability/ae_crisis_tripwire_latest.json (발화월·이탈도·M4 대비·급성도·dedup 원장)",
           "AE 신호 신선화(신규 월) = ae_regime_walkforward.py 재실행 후 본 tripwire가 신규 발화 register",
           "★자본/배포 절대 미상정 — book_state/05_Production 무변경. 급성 crisis 감시 계층 배선일 뿐"))
  ),
  charts = chart,
  footer = sprintf("AE·M4 동일 pin(%s) apples-to-apples · monitoring 배관 · 자본 아님 · 자동조치 없음(도훈 재료)",
                   "WT-D20260718_007_r1"),
  force = TRUE
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, " err=", res$error %||% "none", "\n", sep = "")
if (isTRUE(res$ok)) cat("[tg] SENT for", L$decision_date, "— now run AE_MARK_SENT to dedup\n")
