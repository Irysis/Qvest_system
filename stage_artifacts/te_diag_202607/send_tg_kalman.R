Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages(source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")))
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/te_diag_202607/kalman_ext"

res <- tg_agent_brief(
  agent = "Risk",
  title = "Kalman vs EWMA TE 추정기 대결 — 결론: EWMA 유지 (Kalman 복잡도 미정당)",
  as_of = "2026-07-13",
  sections = list(
    list(emoji = "📌", heading = "요약", type = "text",
         body = paste0(
           "도훈 질문(\"Kalman beta 써봤나\") → 처녀기법 Kalman 2종(local-level 변동성 SV + ",
           "TV-beta)을 어제 TE 진단과 동일 워크포워드 하네스로 대결. 대조군 5/5 정확 재현. ",
           "Kalman-SV가 raw 지표선 이기나(분산비 1.015·오경보 0.9%), 적대검증 결과 이 승리는 ",
           "log-offset로 눈금 level을 맞춘 아티팩트 — 단일 상수 re-baseline이 거의 복제. ",
           "TV-beta는 EWMA 못 이기고 오버레이 성분 흡수도 실패. 진단·결정 재료만(무변경).")),
    list(emoji = "💡", heading = "쉬운 설명", type = "text",
         body = paste0(
           "추적오차(TE)=방어북이 지수와 벌어지는 폭. 이걸 예측하는 '눈금자'로 Kalman filter(상태공간 ",
           "추정, 이론적으로 EWMA의 상위호환)를 처음 시험했다. 결과: Kalman이 표면 점수는 좋지만, ",
           "그 이득의 대부분은 '눈금 높이를 올린' 것뿐이라 훨씬 단순한 상수 재조정으로 똑같이 얻어진다. ",
           "즉 정교한 기법값을 못 한다 — 우리 'EW 천장' 교훈과 같은 형태.")),
    list(emoji = "📊", heading = "Head-to-head (공통창 233개월, 낮을수록/1에 가까울수록 우수)", type = "table",
         df = data.frame(
           추정기 = c("Kalman-SV", "EWMA λ0.97", "Kalman-TVbeta", "현행 상수", "국면조건부"),
           `오경보율` = c("0.9%", "3.6%", "3.6%", "4.1%", "5.9%"),
           `분산비` = c("1.015", "1.103", "1.138", "1.198", "1.294"),
           check.names = FALSE, stringsAsFactors = FALSE),
         max_col_width = 15L,
         notes = c("Kalman-SV paired z² vs EWMA97: t=-5.88 p<0.001 (raw 지표 기준 유의)",
                   "단, 아래 강건성서 이 승리 붕괴")),
    list(emoji = "🔬", heading = "적대검증: Kalman-SV 승리의 강건성", type = "table",
         df = data.frame(
           점검 = c("offset c=0.01", "offset c=0.02", "offset c=0.05", "상수 re-baseline", "centered 지표"),
           결과 = c("분산비 1.091", "분산비 1.015", "분산비 0.899(과대)", "오경보 1.4%(거의복제)", "Kalman 과대·EWMA 최적"),
           check.names = FALSE, stringsAsFactors = FALSE),
         max_col_width = 22L,
         notes = c("승리가 offset(nuisance)에 좌우 = level 튜닝 효과",
                   "implied λ=0.9999 near-static: EWMA보다 더 적응적이지 않음")),
    list(emoji = "🚩", heading = "판정 (TE 감시 기준선 결정 재료)", type = "bullet",
         items = c(
           "권고: EWMA λ0.97 유지 (어제 진단 ⓑ 불변) — Kalman 복잡도 비용 미정당",
           "Kalman-SV: raw 승리는 log-offset level 아티팩트 + 단일 상수로 복제 가능",
           "Kalman-TVbeta: EWMA 못 이김(p=0.061) + 오버레이 흡수 실패(cor -0.03)",
           "핵심 이득은 '눈금 level 상향'(0.19→0.21~0.22)이지 Kalman 기법 아님",
           "어떤 추정기도 최근 실현 급등(0.33)은 못 잡음 — 국면전환은 사후만")),
    list(emoji = "💰", heading = "돈에 뭐가 달라지나", type = "text",
         body = paste0(
           "지금 바뀌는 것 없음. Kalman을 감시 눈금자로 채택하지 않는다는 결론 — 종목·비중·자본 무접촉. ",
           "TE 기준선 교체(EWMA) 결정 자체는 여전히 도훈 판단 대기.")),
    list(emoji = "📂", heading = "산출", type = "text",
         body = "stage_artifacts/te_diag_202607/kalman_ext/ (eval·offset민감도·복제·곡선·adv_summary)")
  ),
  charts = c(file.path(OUT, "chartK1_estimator_ranking.png"),
             file.path(OUT, "chartK2_rolling_pred_vs_realized.png")),
  footer = "진단 전용 · READ-ONLY · book/monitoring 무변경 · governor 정지 존중"
)
cat("[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes, " err=", if(is.null(res$error)) "-" else res$error, "\n", sep="")
