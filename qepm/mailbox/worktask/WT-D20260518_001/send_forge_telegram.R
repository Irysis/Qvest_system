#!/usr/bin/env Rscript
# ============================================================================
# Forge cycle Telegram brief — WT-D20260518_001 (v2 TRUE OOS FAIL honest)
# v6 SOT 정합 (qvest-telegram skill)
# ============================================================================

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Forge",
  title = "약세 예측 엔진 v2.0 — TRUE OOS walk-forward 정합 후 honest FAIL (Layer 6 overlay admission 부적격)",
  sections = list(
    list(type = "summary",
         body = "발견형 작업 WT-D20260518_001 약세 예측 v2.0 PIT-clean OOS 적용 후 baseline 대비 음의 알파 입증 정직 보고."),

    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "목적은 약세 예측 엔진 v2.0 (4축 보정 + 14 자질) 정합 백테스트",
           "방법은 5 윈도우 × 5 모형 × 5 보정 × 3 문턱 = 375 시행",
           "Codex 1차 거부 첫 우려 (학습 혼입) 인정 후 2차 진정 외표본 재실행",
           "결과 진정 외표본 1안 샤프지수 0.139 대비 베이스 0.176 차 -0.037 음수",
           "결론은 약세감지 v2.0 채택 부적격으로 정직 보고"
         )),

    list(type = "kv", emoji = "📉", heading = "진정 외표본 결과 (220 시점)",
         kv = list(
           "샤프지수 1안" = "0.139",
           "샤프지수 베이스" = "0.176",
           "샤프지수 차" = "-0.037 (음, 부적격)",
           "최대낙폭 1안" = "-78.6%",
           "최대낙폭 베이스" = "-78.6%",
           "최대낙폭 차" = "0퍼센트포인트 (위기 시점 놓침)",
           "연복리수익률 1안" = "0.45퍼센트",
           "회전율 연간 1안" = "0.30 (상한 6.0)"
         )),

    list(type = "kv", emoji = "🔬", heading = "통계 검정 (정합 외표본)",
         kv = list(
           "DM 통계량" = "-1.211",
           "DM 한쪽 p값" = "0.113 (경계선)",
           "1안 채택 문턱 (0.15 이하)" = "경계선 통과",
           "1안 대체 문턱 (0.05 이하)" = "부적격",
           "다중검정 t값 3 이상 갯수" = "0/5 (전체 부적격)",
           "다중검정 t값 5종" = "-1.61 / -1.85 / 결측 / -0.99 / 0.65 모두 음수",
           "디플레이티드 샤프" = "-3.59 베이스 -3.39 대비 악화",
           "공리 1 조건부 방어 검정" = "부적격 (위기 9건 발화나 최대낙폭 개선 0)"
         )),

    list(type = "kv", emoji = "⚠️", heading = "1차 학습혼입 vs 2차 외표본 격차",
         kv = list(
           "1차 샤프 차 (혼입)" = "+0.197",
           "2차 샤프 차 (외표본)" = "-0.037",
           "샤프 차 격차" = "-0.234",
           "1차 DM 통계량" = "-4.92 강한 신호",
           "2차 DM 통계량" = "-1.21 약한 신호",
           "1차 다중검정 t>3" = "2/5",
           "2차 다중검정 t>3" = "0/5",
           "원인" = "기간별 모형이 학습기 264건 자기 예측"
         )),

    list(type = "bullet", emoji = "✅", heading = "Codex 1차 처리 8건",
         items = c(
           "1번 학습 혼입 인정, 외표본 재실행 적용",
           "2번 일정표 277 대 437 불일치 인정 수정",
           "3번 미래 라벨 emit 인정, 차단 적용",
           "4번 차트 부재 인정, 3 차트 발행",
           "5번 다중검정 미달 부분 인정",
           "6번 디플레 샤프 음수 부분 인정",
           "7번 베이스 비교 범위 부분 인정",
           "8번 M4 대리 변수 부분 인정"
         )),

    list(type = "bullet", emoji = "📊", heading = "5 Stage 완주 정합 (v2 TRUE OOS)",
         items = c(
           "Stage 1: 14 feature inherit (44 설계 중) + 84 PIT audit",
           "Stage 2: walk-forward 5 window (W1~W5) + Pesaran-Timmermann 3 국면",
           "Stage 3: 375 trial run (5 model × 5 calib × 3 thr × 5 window)",
           "Stage 4: G1.5 strict 0 → relaxed 12 통과 honest",
           "Stage 5: p_bad_t TRUE OOS 220 sig_date emit + M05 + DM + V_Path"
         )),

    list(type = "bullet", emoji = "🔐", heading = "공리 정합",
         items = c(
           "AX-002 자기 합성 미사용 + 외표본 walk-forward",
           "AX-001 v2 조건부 방어 외표본 부적격",
           "AX-007 overlay 역할 예외 정합",
           "AX-008 Codex 1+2차 거부 + Forge 부적격 정직",
           "순수 함수 검사 통과 (3 package 일치)"
         )),

    list(type = "bullet", emoji = "📌", heading = "결론 다음 단계",
         items = c(
           "Forge 결론: 외표본 부적격 정직 보고",
           "1차 +0.197은 학습 혼입, 2차 -0.037 정합 결과",
           "재설계 경로: 30 추가 자질 + 국내 팩터 자료",
           "본 산출은 발견 단계 완주 (헌장 10조 v1.8)",
           "Architect 검증 의뢰 시 정직 부적격 통합",
           "잔존 과제: 약세감지 재설계 또는 대안 탐색"
         ))
  )
)
