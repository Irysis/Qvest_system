setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create(
  hypothesis_title = "중립화가 베타-drag 채널을 제거하면 IC가 PORT_t 로 전이되는가 — Q01 섹터+사이즈 중립 제외필터",
  hypothesis_description = paste(
    "WT-D20260808_001(FQ-122) NP-1 파생. ★이 가설은 직전 라운드가 **확립한 기전의 직접 귀결**이다(자가발전 경로).",
    "직전 라운드 확립 사실: (1) 제외필터 최상위 분위 β = 0.765/0.732 vs 유니버스 0.979/0.981 (t -12.71/-19.88) = β-drag 실측 확립.",
    "(2) 개인 순매수가 필터 z 하위에 집중하며 log(시총) 통제 후에도 잔존 = 사이즈 대용 배제.",
    "(3) 전 arm INCONCLUSIVE_UNDERPOWERED — 필요 연효과 +4.47%/+3.02% 대비 관측 0.79%/0.81%.",
    "(4) 부수: D03 은 rank-IC Harvey-t +3.50 인데 5분위 평균수익 Q1 +13.1% -> Q5 +8.0% 단조 감소(monotonicity 0.25)",
    "= 고변동 꼬리의 양의 왜도가 평균을 올리는데 rank-IC 가 못 보는 구조. IC->PORT_t 전이 벽의 산술적 정체.",
    "★본 WT 의 가설: β-drag 가 전이 실패의 원인이라면 그 채널(섹터+사이즈)을 중립화로 제거했을 때 IC 가 PORT_t 로 전이돼야 한다.",
    "직전 라운드 실측이 이미 방향을 지지한다 — 중립화 시 Q01 rank-IC 1.28배·Harvey-t 5.34(중립화 전 대비 강화, RF-A4 역방향).",
    "★반증: 중립화 후에도 PORT_t 가 전이되지 않으면 β-drag 는 전이 벽의 원인이 아니며, 벽은 재료·채널 무관한 구조라는 기존 확립사실(2026-07-13 재료-불변성)이 재확인된다.",
    "★검정력: 착수 전 required_effect() 로 필요 효과크기를 기록하고 미달이면 설계를 바꾼다. 직전 라운드가 검정력 미달로 판정 유보된 직접 교훈.",
    "★MAX5/vol63 재발견 배제 의무: 직전 라운드가 배제 실패를 명시했다. 본 라운드는 MAX5 원변수 통제를 포함한다."),
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
cat("[wt2] created:", wt_id, "\n")
writeLines(wt_id, "stage_artifacts/WT_D20260808_001/wt2_id.txt")
