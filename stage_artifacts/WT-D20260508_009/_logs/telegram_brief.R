#==============================================================================
# WT-D20260508_009 Risk Research Telegram Brief
# v6.3 SOT 준수 (한글 key / 약어 grep 차단)
#==============================================================================

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

WT_ID <- "WT-D20260508_009"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)

suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
risk_pkg <- fromJSON(file.path(WT_DIR, "risk_package.json"), simplifyVector = FALSE)

ms_log <- risk_pkg$sigma_method_details$method_shopping$method_log

# 추정기 비교 표 (한글, 2 cols 제약)
estim_df <- data.frame(
  추정기 = sapply(ms_log, function(m) {
    n <- m$name
    switch(n,
           "sample" = "표본",
           "ledoit_wolf_oas_hrp" = "OAS변형",
           "ledoit_wolf_constcor" = "Honey상관",
           "gerber_rmt" = "Gerber",
           n)
  }),
  결과 = sapply(ms_log, function(m) {
    sel <- ifelse(isTRUE(m$selected), "선택", "기각")
    cn <- if (!is.null(m$kappa_exact) && !is.na(m$kappa_exact)) sprintf("%.0f", m$kappa_exact)
          else if (!is.null(m$kappa_default_R)) sprintf("%.0f", m$kappa_default_R)
          else "NA"
    sprintf("κ%s %s", cn, sel)
  }),
  stringsAsFactors = FALSE
)

cat("Estimator df preview:\n")
print(estim_df)

# 핵심 결과 kv (named list, 한글 key)
kv_core <- list(
  "공분산 추정기" = "Honey 상관 (조건수 753 정보 0.24)",
  "공분산 차원" = sprintf("%d종 × 252일", risk_pkg$sigma_method_details$n_assets),
  "위험설명력" = sprintf("주성분 5개 = %.1f%% (시장 24%%)",
                              risk_pkg$risk_summary$factor_coverage_r2_top5_pc * 100),
  "꼬리손실 95%" = "후보 -10.35% / Hybrid -6.76%",
  "분산비율" = sprintf("%.2f (상위 20종 동일가중)",
                          risk_pkg$risk_summary$diversification_ratio_alpha_top20),
  "직교성" = "월간 상관 0.002 (Hybrid 대비)",
  "공리 검증" = "위기 정보계수 양 0.125 / 3축 충족"
)

# 잔여 위험 bullet (≤80자)
bullet_risk <- list(
  "조건수 753 — 본질 한계 후속 가중치 경계 + l1 정규화 권장",
  "꼬리손실 후보 동일가중 -10.35% > 상한 2.5% — 닷컴 -27.66% 정량",
  "반도체 14/20 = 70% 집중 — 사이클 7 상위고유값 확장 22 → 27%",
  "BAB 단독 슬리브 t값 1.63 — 다중슬리브 합성으로만 통과 retain",
  "위기 페어 상관 0.236 vs 평시 0.123 — 단조 증가 분산 부담",
  "Architect 3rd 검증 미실행 — 공리 008 1.5/3 부분"
)

# 다음 단계 bullet
bullet_next <- list(
  "Optimizer 단계 인계 — 가중치 결정 본 risk 영역 외",
  "Forge 백테스트 — 정확한 portfolio-level 꼬리/위기 영역",
  "Architect 추가 source — 도훈 명시 시 spawn"
)

# 학술 근거 bullet (각 줄 영어 약어 1건 이내)
bullet_ref <- list(
  "Frazzini-Pedersen 2014 베팅어게인스트베타 / Asness 등 2014 품질빼기쓰레기",
  "Novy-Marx 2013 / Sloan 1996 / Cooper-Gulen-Schill 2008",
  "Ledoit-Wolf 2004 Honey 상관 수축 / Pfaff 2016 위험모델링"
)

sections <- list(
  list(heading = "연구 컨텍스트", type = "summary",
       body = "BAB 다축 품질 멀티 슬리브 공동위험 진단 — Codex REJECT 자율 분류 처리"),
  list(heading = "공분산 추정기 비교", type = "table", df = estim_df),
  list(heading = "핵심 결과", type = "kv", kv = kv_core),
  list(heading = "잔여 위험", type = "bullet", items = bullet_risk),
  list(heading = "학술 근거", type = "bullet", items = bullet_ref),
  list(heading = "다음 단계", type = "bullet", items = bullet_next)
)

result <- tg_agent_brief(
  agent = "Risk",
  title = sprintf("%s 공동위험 진단 완료 — Honey 상관 조건수 753", WT_ID),
  sections = sections,
  as_of = format(Sys.Date(), "%Y-%m-%d"),
  decode_jargon = TRUE,
  decode_mode = "inline_first",
  smart_break = TRUE
)

cat("\n=== Telegram dispatch result ===\n")
print(result)
