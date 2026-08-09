## WT 발급 — FQ-161 후속: M26 전이 벽 채널 분해
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/worktask_manager.R")

wt_id <- wt_create(
  theme = "m26_transition_channel_decomposition",
  hypothesis_title = "M26_Revenue_Mom 의 IC->PORT_t 전이 갭이 어느 채널에서 발생하는가",
  hypothesis_description = paste(
    "WT-D20260808_002 가 M26_Revenue_Mom 을 MATERIAL_QUALIFIED 로 확정했다:",
    "FMB NW3 t=+2.555(283개월) · T+1 실행앵커 t=+2.305(유지율 0.902) · placebo p=0.005 ·",
    "기존 컨센서스 3종 대비 max spearman 0.215(재탕 아님) · rank-IC t_NW3=+2.971.",
    "그러나 전이에서 cap-w PORT_t=+1.544(잔차 +1.443) 로 HARD 2.95 미달이다.",
    "인계 큐 판정: '재료 품질에 흠이 없는데 IC t 2.97 -> PORT_t 1.544 로 갈라지는 가장 깨끗한 사례'.",
    "본 라운드는 그 갭의 **채널**을 분해한다. 상호배타 3채널을 결과 도착 전에 사전선언하고,",
    "각 채널의 판정 규칙과 그에 따른 소비면 라우팅을 함께 고정한다.",
    "CH-A 비용(구현): 동일 선별에서 cost 15bps -> 0bps 반사실. turnover 11.74/yr 가 gross 를 잠식하는가.",
    "CH-B 꼬리/단조성: FMB/rank-IC 는 횡단면 전체 기울기인데 top-25 long-only 는 최상위 꼬리만 수확한다.",
    "        기울기가 하위 분위(공매도 측)에서 나오면 long-only 는 구조상 수확 불가.",
    "CH-C breadth/슬롯: 신호가 확산형이면 25슬롯이 과집중이다. top_n 확대는 **진단 전용**이며",
    "        max 25 는 고정 축(INV-7) 이므로 어떤 N 도 자본 주장으로 승격 금지.",
    "본 라운드는 재료 자격 재판정이 아니다 — 자격은 WT-D20260808_002 에서 확정됐고 여기서 재측정하지 않는다.",
    "산출물은 전부 canonical_screen / canonical_screen_diag 라벨이며 자본 주장 없음."),
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
cat("[wt] created:", wt_id, "\n")
writeLines(wt_id, "stage_artifacts/c14_revsurprise/wt_id_transition.txt")
