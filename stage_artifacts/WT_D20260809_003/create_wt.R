setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create(
  theme = "transition_wall_shape_classification",
  hypothesis_title = "전이 벽 형태 분류 — 무엇이 '단조(상단 정보 有)' 와 '혹(상단 정보 無)' 를 가르는가",
  hypothesis_description = paste(
    "2026-08-09 하루에 독립 두 라운드가 정반대 분위 형태를 실측했다.",
    "M26_Revenue_Mom (WT-D20260809_001): decile 단조성 spearman +0.879, D10 연초과 +6.550%(t +2.822) = 상단 정보 有.",
    "중립 Q01_EB (WT-D20260808_003): EW 대비 5분위 [-3.81 +1.37 +3.05 +1.78 -2.41] = 혹, 최상위가 EW 에도 뒤짐 = 상단 정보 無.",
    "그러나 두 관측은 프레임이 다르다 — 10분위/전표본/원신호 vs 5분위/post-2015/중립화.",
    "따라서 '벽이 이질적이다' 는 아직 확립이 아니라 가설이다. 형태 차이가 재료 때문인지 프레임 때문인지 미분리.",
    "본 라운드는 4재료(M26_Revenue_Mom / Q01_EB / D03_EWMA / M01_PATHQ)를 **동일 행** 위에 올리고",
    "(내부조인 69,282행 x 282개월 x 630종목, 월중앙 284종목 = decile 당 28) 분위 프로파일을 재산출한다.",
    "분위 해상도(5/10) x 창(전표본/post-2015) x 처리(원신호/중립화) 를 교차해",
    "형태가 재료 속성인지 프레임 산물인지 분리한다.",
    "진단 라운드 — 자본 주장 없음. 어떤 재료도 본 라운드에서 자격 판정을 받지 않는다."),
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return")
cat("[wt] created:", wt_id, "\n")
writeLines(wt_id, "stage_artifacts/WT_D20260809_003/wt_id.txt")
