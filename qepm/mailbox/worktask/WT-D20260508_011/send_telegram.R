#!/usr/bin/env Rscript
# WT-D20260508_011 Alpha Research Telegram Brief (v6.3 SOT)

# Project root
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "코스피200 옵션 chain 직접 변동성 위험 프리미엄 알파 발굴 — 정직한 실패",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "16년 옵션 chain 직접 4 모형 정밀 구현. PIT-strict 적용 후 정보계수 0.0037 / 다중검정 t값 0.47. 명백한 실패."),

    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "[목적] 한국 옵션 직접 4 모형 정밀로 4번째 직교 알파 발굴",
           "[모형] Bakshi 2003 / Carr-Wu 2009 / Bollerslev 2009 / VKOSPI 재구축",
           "[데이터] 한국거래소 16년 4023일 / 618만 행 직접 캐시",
           "[방법] 횡단면 8 시도 + ML XGBoost 11 변수 5분할 검증",
           "[결론] 1번 사이클 패턴 재현 — 4번째 source 다른 경로 권고"
         )),

    list(type = "kv", emoji = "📊", heading = "핵심 비교 (정직한 정량)",
         kv = list(
           "정보계수" = "0.0037 (실패 < 0.04)",
           "정보계수 안정성" = "0.033 (실패 < 0.20)",
           "다중검정 t값" = "0.47 (실패 < 3.0)",
           "Q5 샤프지수" = "0.568 / t값 1.94",
           "디플레이티드 샤프" = "0.615 (통과)",
           "회전율 연" = "548% (통과 < 600%)"
         )),

    list(type = "bullet", emoji = "🚩", heading = "Codex 비판 + 적용 수정",
         items = c(
           "Codex 거부 입장 (높음 5건 + 중간 3건)",
           "1번 알파 시계열 누락 — 일자×종목 144 시점 재작성",
           "4번 시점 정합 보수 — 옵션 신호 직전월 적용",
           "5번 회전율 760% 위반 — 분기 리밸런싱 548% 통과",
           "정보계수 0.025→0.0037 86% 감소 — 동월 신호 누출"
         )),

    list(type = "bullet", emoji = "✅", heading = "보존 인프라 (학술 자산)",
         items = c(
           "16년 한국거래소 옵션 직접 캐시 4023일 / 618만 행",
           "VKOSPI 자체 재구축 — 2020년 92 / 2026년 110 정합",
           "Bakshi 2003 + Carr-Wu 2009 + Bollerslev 2009 정밀 구현",
           "월간 변동성 위험 프리미엄 신호 + 재구축 시계열 영구 보존"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션 (Q-Lead 결정)",
         items = c(
           "현 옵션 횡단면 경로 종료",
           "1번 사이클 동일 패턴 — 한국 상위 대학 한계 재현",
           "4번째 source 우회: 방어 저변동 다층 슬리브 또는 원자재",
           "옵션 인프라는 후속 파생 연구 자산 보존"
         ))
  ),
  charts = NULL
)
