## WT 발급 — M26_Revenue_Mom 증분 판정 (C14 라운드의 재료 정정판)
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/worktask_manager.R")

wt_id <- wt_create(
  theme = "revenue_surprise_increment",
  hypothesis_title = "매출 모멘텀(M26_Revenue_Mom)의 이익-컨센서스 3종 대비 횡단면 증분",
  hypothesis_description = paste(
    "원 사전등록(stage_artifacts/c14_revsurprise/prereg.json)은 C14_Revenue_Surprise 를 대상으로 작성됐으나,",
    "Q-Lead 사전 확인 실측에서 전제가 틀린 것으로 확인됐다:",
    "(1) C14 는 factor_db 최신월 819,411행·319종 중 부재이고 442개 월 파일 전 구간 0건.",
    "(2) 원인은 compute_consensus.R:238 의 if('revenue_fy1' %in% names(cons)) 조건부 블록이",
    "    입력 미탑재 시 통째로 조용히 스킵되는 것. registry 등재·빌더 코드·원천(.cache/consensus/revenue_fy1.parquet)은 전부 실재.",
    "(3) 같은 재료·같은 공식의 팩터가 M26_Revenue_Mom 으로 이미 산출 중이다",
    "    (compute_momentum.R:376 의 rev_mom := (rev_now - rev_lag)/abs(rev_lag) 가 C14 식과 동일).",
    "즉 C14 는 신규 재료가 아니라 중복 등재이며, 침묵한 쪽이 중복분이다.",
    "따라서 대상 팩터를 M26_Revenue_Mom 으로 교체하되 판정 규칙·문턱·분기는 원 사전등록 그대로 불변으로 승계한다.",
    "주판정량: fwd_ret ~ z(C01_SUE)+z(C02_EPS_Chg_1m)+z(C04_ESBR)+z(M26_Revenue_Mom) 의",
    "z(M26) 계수 Fama-MacBeth NW(lag3) t. pooled OLS 금지. 전표본 횡단면(분할 금지).",
    "문턱 |t|>=2.0 은 재료 자격 판정이며 자본 게이트(HARD 3종) 아님.",
    "REDUNDANT 분기: t 유의해도 기존 3종과 spearman >= 0.9 면 재탕 처분."),
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
cat("[wt] created:", wt_id, "\n")
writeLines(wt_id, "stage_artifacts/c14_revsurprise/wt_id_m26.txt")
