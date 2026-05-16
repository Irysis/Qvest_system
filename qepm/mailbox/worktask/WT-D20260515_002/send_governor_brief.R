# Governor WT-D20260515_002 FINAL Telegram brief
# Lifecycle FINAL summary — Sequential Admission REJECT + book_state v2.3 RETAIN

suppressWarnings(suppressMessages({
  src_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "02_Infrastructure/telegram/telegram_notify.R"
  )
  source(src_path)
}))

# Charts inherit from judge stage (lockbox marker verified)
chart_dir <- file.path(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "qepm/mailbox/worktask/WT-D20260515_002/output"
)
equity_curve_chart <- file.path(chart_dir, "equity_curve.png")
oos_zoom_chart <- file.path(chart_dir, "oos_zoom_chart.png")

charts <- character(0)
if (file.exists(equity_curve_chart)) charts <- c(charts, equity_curve_chart)
if (file.exists(oos_zoom_chart)) charts <- c(charts, oos_zoom_chart)

result <- tg_agent_brief(
  agent = "Governor",
  title = "WT-D20260515_002 GOVERNOR FINAL — REJECT BLEND book_state v2.3 retain",
  sections = list(
    list(
      heading = "Summary",
      type = "bullet",
      items = c(
        "Lifecycle FINAL — 6/6 단계 모두 Codex 검토 후 확정 완료",
        "최종 결정 거절 (Judge 거절 결정 그대로 수용)",
        "북 상태 v2.3 유지 — 단일 슬리브 100 퍼센트 그대로 유지",
        "Codex 첫 지적 수용: 부분 대체 시나리오 (제안 행위 기준 분류)",
        "Iter 5 선례 적용 — 결과 기준 라벨 아닌 제안 행위 기준 분류",
        "주된 규칙 직접 비교: Sharpe DSR MDD 회전율 모두 단일 슬리브 우위",
        "방향 일치 5소스: Forge Optimizer 그리고 Codex 3회 라운드 전원"
      )
    ),
    list(
      heading = "Metrics",
      type = "table",
      df = data.frame(
        Axis = c(
          "Sharpe 84개월 블렌드",
          "Sharpe 84개월 단일슬리브",
          "Sharpe 256개월 정본",
          "84개월 vs 256개월 드리프트 퍼센트",
          "DSR z 전략수준 N=12 블렌드",
          "DSR z 전략수준 N=12 단일슬리브",
          "MDD 퍼센트 블렌드",
          "MDD 퍼센트 단일슬리브",
          "연 회전율 블렌드 왕복",
          "연 회전율 상한",
          "CVaR95 월간 블렌드",
          "CVaR95 월간 상한",
          "전략수준 미충족 축 개수",
          "Sharpe 목표 달성률 퍼센트"
        ),
        Value = c(
          "0.5579",
          "2.0054",
          "1.9536",
          "-2.65 측정정합 밴드 내",
          "-0.29 미충족",
          "+3.43 강한 통과",
          "-27.21",
          "-14.40",
          "13.07 상한 초과",
          "6.0",
          "-11.21 상한 초과",
          "-10.00",
          "6 of 8",
          "97.9 단일슬리브 유지"
        ),
        stringsAsFactors = FALSE
      )
    ),
    list(
      heading = "Risks",
      type = "bullet",
      items = c(
        "Codex 거버너 라운드 수정요청 거부권 없음 — 6 지적 수용 처분 완료",
        "5건 수용수정 + 1건 부분수용 + 0건 반박 (Charter 제8조 준수)",
        "AX-008 정량적 통과 1/3 (Forge 단독) — Architect 미소환",
        "거절 결정에서는 AX-008 호출 면제 (Charter 제10조 + L-307 선례)",
        "5단계 누적 Codex 44 지적 / 중요도 높음 27건 모두 수용 처리",
        "Q-Lead 에스컬레이트 5회 누적 발화 유지 (Codex 도전 보존)",
        "잔여 리스크 6: 5스펙 / 거래대금-지수 / 회귀증명 / Architect / lockbox",
        "에코 챔버 경고 + 표본편향 인과 진술 경험적 관찰로 격하"
      )
    ),
    list(
      heading = "Next",
      type = "bullet",
      items = c(
        "5월 운용 가중치 그대로 — 위험 자산 70 + 현금 30 (5월 13일 발효)",
        "상위10: 삼성전자 4.78 / 삼성SDI 4.65 / SK하이닉스 4.37 / 에코프로비엠 4.29",
        "프로덕션 단일 슬리브 정본 유지 — 강등 없음",
        "Path D 차기 사이클 권고 (Judge 승인확률 0.45 가장 높음)",
        "방어형 3 소스 대체: 한국 10년 국채 / TSMOM / 스태그플레이션",
        "L-280 한국 국채 선례 + L-281 TSMOM 직교 0.077 선례 활용",
        "차기 의무 10건: Architect 소환 + 거래대금-지수 사전검증 + 회귀",
        "DSR 동일 N + 정본 산출물 경로 계약 + 가중치 파일 경로",
        "Sharpe 목표 잔여 격차 0.0464 — 단일 슬리브 1.9536 유지",
        "L-CANDIDATE 메모리 등재 대기 (Charter 제8조 5 수용 체인 준수)"
      )
    )
  ),
  charts = if (length(charts) > 0) charts else NULL,
  force = TRUE
)

cat("[governor_brief] dispatch result:\n")
print(result)
