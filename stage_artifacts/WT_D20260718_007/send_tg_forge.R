#!/usr/bin/env Rscript
Sys.setlocale("LC_ALL","English_United States.utf8")
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/telegram/telegram_notify.R")
ST <- "stage_artifacts/WT_D20260718_007"
res <- tg_agent_brief(
  agent="Alpha",
  title="WT-D20260718_007 D3 forge 측정 — 교집합 오버레이 calmar-graduation (자본 아님·측정만)",
  as_of="2026-07-19",
  sections=list(
    list(emoji="📌", heading="한 줄 결론 (calmar 게이트 통과·복합 졸업 미달)", type="bullet",
         items=c("D3 교집합 오버레이를 build_bt_result 10요소로 권위 측정(인컴번트 대비)",
                 "손익비 게이트 0.64 통과(2.289)·인컴번트 2.073 대비 +10.4% 개선·최대낙폭 -18.7→-17.0%",
                 "그러나 복합 졸업은 미달 — oos_retention 0.283 < 0.7(밴드 미달)",
                 "★핵심: oos 미달이 인컴번트도 동일(0.282) = carrier 속성(2019+ 알파 감쇠)·오버레이 무관",
                 "→ D3는 인컴번트 오버레이의 손익비 정제(전 지표 지배)이나 자본 졸업 자격 신설 아님")),
    list(emoji="📊", heading="forge-authoritative 지표 (월간·연율12·15bps)", type="kv",
         kv=list(
           "손익비 (인컴번트→D3)"="2.073 → 2.289 (게이트 0.64 통과)",
           "최대낙폭 (인컴번트→D3)"="-18.7% → -17.0%",
           "샤프지수 (인컴번트→D3)"="1.809 → 1.815",
           "초과수익 다중검정t (인컴/D3)"="4.223 / 4.221 (동일)",
           "표본외 유지율 (인컴/D3)"="0.282 / 0.283 (양쪽 미달·동일)",
           "사전구간 반증 판정"="반증 아님(구간 내·표본외 샤프 1.79 in [1.44,2.65])")),
    list(emoji="🚦", heading="졸업 게이트별 판정", type="kv",
         kv=list(
           "손익비 게이트 (≥0.64)"="2.289 → 통과(인컴번트 대비 개선)",
           "표본외 유지율 게이트 (≥0.7)"="0.283 → 미달(carrier 감쇠·오버레이 무관)",
           "다중검정 조정 샤프 게이트"="미적용(가설주도 chain, 시도수 9 기록)",
           "사전구간 반증검정"="반증 안 됨(구간 내)",
           "복합 자본 졸업"="미달(유지율) — 단 D3는 손익비 지배 후보")),
    list(emoji="🚩", heading="자가 적대검증·정직", type="bullet",
         items=c("초과수익 비유의 불변 — return 졸업 주장 안 함(측정은 손익비 축만)",
                 "oos 미달은 carrier(STR_1715 2019+ 알파감쇠) 속성 — D3/인컴번트 동일(0.283/0.282)",
                 "D3는 전 book 지표에서 인컴번트 지배(손익비/낙폭/샤프/연복리)이나 자본 자격 신설 못함",
                 "production 코드 인컴번트 대비 측정(parity 확인)·동월 vintage 저장패널 미사용")),
    list(emoji="➡️", heading="도훈 admit 결정 재료 (자본 아님·측정만)", type="bullet",
         items=c("D3 교집합 = 인컴번트 오버레이의 손익비 지배 swap-in 후보(무수 규칙·과적합 없음)",
                 "복합 졸업 미달의 병목=carrier 알파 retention(오버레이로 해결 불가)",
                 "수익 상승은 selection 계층 과제 — 타이밍/오버레이 계층 상한 확정",
                 "배포는 도훈 수동 book 결정 — 본 측정은 자격 판정만"))
  ),
  charts=c(file.path(ST,"chart_d3_calmar.png"), file.path(ST,"chart_d3_oos.png")),
  footer="측정=build_bt_result 10요소(backtested)·pin=WT-D20260718_007_r1 · 판정=손익비 게이트 통과·복합졸업 미달(oos carrier) · 자본=도훈 수동",
  force=TRUE
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, " err=", res$error %||% "none", "\n", sep="")
