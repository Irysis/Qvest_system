Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages(source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")))
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/te_diag_202607"

res <- tg_agent_brief(
  agent = "Risk",
  title = "라이브 북 TE 과소추정 진단 — 실현 0.332 vs 예측 0.190 (1.75x)",
  as_of = "2026-07-13",
  sections = list(
    list(emoji = "📌", heading = "요약", type = "text",
         body = paste0(
           "TE 경보 원인 진단. \"예측 0.190\"은 위험모델 예측이 아니라 full-sample 실현 TE 상수. ",
           "최근 active 변동성이 전기간 대비 분산으로 3.07배 실제 급등 — melt-up × 방어 오버레이 ",
           "상호작용이 원인. 모델 버그 아님. 진단 재료 (book/weight 무변경).")),
    list(emoji = "💡", heading = "쉬운 설명", type = "text",
         body = paste0(
           "방어북(주식 70%·위기 시 현금↑)은 지수와 다르게 움직이고, 그 벌어짐이 추적오차(TE)다. ",
           "2025-26 초대형 반도체주가 지수를 +91%·+126% 폭등시켜 지수 변동성이 2배가 됐고, ",
           "방어북이 이를 못 따라가 벌어짐이 커졌다. 예측치가 '과거 평균' 고정값이라 못 담아 경보.")),
    list(emoji = "📊", heading = "갭 성분분해 (trailing-21M 분산 기여)", type = "table",
         df = data.frame(
           성분 = c("Selection(base가 지수 못따라감)", "Overlay 노출스위칭 계열", "  └ melt-up 8개월 집중", "  └ 최악 1개월(2026-06)"),
           기여 = c("70%", "30%", "51%(시간축)", "39%"),
           stringsAsFactors = FALSE),
         max_col_width = 26L,
         notes = c("2026-06: 지수 +33.4% vs 북 +7.2% = active -26.1%",
                   "corr(sel,overlay) 전기간 -0.11 → 최근 +0.60 동조증폭")),
    list(emoji = "🔬", heading = "재추정: 예측기 워크포워드 (오경보율·현예측TE)", type = "table",
         df = data.frame(
           추정기 = c("현행 상수", "EWMA λ0.97", "국면조건부(순진)"),
           `오경보율·TE` = c("6.1% · 0.180", "3.3% · 0.221", "10.6% · 0.121"),
           check.names = FALSE, stringsAsFactors = FALSE),
         max_col_width = 18L,
         notes = c("robust 중앙값 TE 예측 ≈ 0.22~0.27 (국면 지속 무관)",
                   "국면조건부 순진판=최악(melt-up이 NORMAL로 라벨)")),
    list(emoji = "🚩", heading = "판정 재료 (실행은 도훈)", type = "bullet",
         items = c(
           "권고: ⓑ 추정기 교체 — 상수 0.190 → EWMA λ0.97(0.221). 오경보율 절반 실측",
           "ⓐ 예측치만 갱신: 최저비용이나 다음 국면전환서 또 lag",
           "ⓒ 국면조건부: 순진판 실측 열위 → 기각",
           "경보는 실질 false-positive 아님 — TE 실제 3배 급등(실존 melt-up)",
           "라이브는 정상: trailing SR 3.25 PASS_PLUS. 자본/전략 무변경")),
    list(emoji = "💰", heading = "돈에 뭐가 달라지나", type = "text",
         body = paste0(
           "지금 당장 바뀌는 것 없음. '위험 눈금자'를 국면에 맞게 재조정하자는 진단이지 종목·비중·",
           "자본을 건드리는 게 아니다. EWMA로 바꾸면 알려진 방어 특성 반복 오경보↓, 진짜 새 위험은 ",
           "계속 포착. 실행 여부는 도훈 판단.")),
    list(emoji = "📂", heading = "산출", type = "text",
         body = "04_Research/01_reports/te_reestimation_diagnosis_20260713.md + stage_artifacts/te_diag_202607/")
  ),
  charts = c(file.path(OUT, "chart1_te_rolling.png"), file.path(OUT, "chart2_variance_decomp.png")),
  footer = "진단 전용 · READ-ONLY · governor 정지 존중 · Judge 재판정 없음"
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes, " err=", if(is.null(res$error)) "-" else res$error, "\n", sep="")
