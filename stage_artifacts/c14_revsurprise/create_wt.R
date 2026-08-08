setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create(
  hypothesis_title = "IC 양성·전이 음성 팩터의 슬롯 없는 소비 — 타이브레이커/제외필터 한계기여",
  hypothesis_description = paste(
    "FQ-122 (프론티어 큐, 2026-08-02 등재, owner 미배정, data_gate 없음, in-flight 중복 없음 확인).",
    "확정된 전제(WT-021): D03_EWMA 는 rank IC t +3.71 로 횡단면 정보가 유의하나 top-25 slot 을 주면 tail-전이 PORT_t −1.73 으로 유해하다.",
    "Q01_EB 도 같은 형태(IC t +2.21 / PORT_t −0.21).",
    "즉 '신호가 없다'가 아니라 '이 소비 경로가 틀렸다'는 형태이며, 2026-08-02 에 같은 계통이 실증된 바 있다",
    "(MAX5: 랭킹으로는 사망했으나 제외필터로는 ΔIR +0.169·MDD −11.4%pt).",
    "본 WT 는 슬롯을 주지 않는 두 소비면의 한계기여를 실측한다:",
    "(a) 단일 최강 팩터의 선별 경계(rank 20~40) 내 동순위 타이브레이커,",
    "(b) 하위 분위 제외 필터.",
    "판정은 단일(현행) 대비 paired 한계기여이며, 자본 자격이 아니라 '이 재료를 회수할 수 있는가'를 묻는다.",
    "부수로 optimizer 단계에서 FQ-090(전이층 손잡이 격리 — 동일 신호 위 보유밴드/리밸주기)을 함께 답한다.",
    "실패해도 'IC 양성 자원의 소비 불가'가 확정되어 risk-research 위험축 재배치 근거가 된다."),
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
cat("[wt] created:", wt_id, "\n")
st <- wt_status(wt_id)
cat("[wt] status:", if(is.list(st)) st$status else as.character(st), "\n")
writeLines(wt_id, "stage_artifacts/c14_revsurprise/wt_id.txt")
