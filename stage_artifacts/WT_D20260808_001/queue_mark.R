suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries; i <- which(sapply(E, function(x) isTRUE(identical(x$id,"FQ-122"))))[1]
cat("[q] FQ-122 인덱스:", i, "\n")
E[[i]]$round_20260808 <- list(
  wt = "WT-D20260808_001",
  state = "measured_pending_adversarial_verification",
  what_ran = paste(
    "alpha-hypothesis(fable) -> alpha-research(opus) 완주. 제외필터/타이브레이커 2 arm 사전등록.",
    "타이브레이커 arm 은 사전등록 F4 킬스위치 발화로 **측정하지 않음**(밴드 기울기 <= 0). 이는 측정 결과가 아니라 사전 규약 집행이다."),
  verdict_status = paste(
    "★수치·판정은 본 항목에 아직 기록하지 않는다 — AX-008 3-source 중 3번째(독립 적대검증)가 진행 중이다.",
    "렌즈 4종(계산재현/PIT/통계/대안설명) + 완전성 비판 + 종합.",
    "검증 종료 후 생존한 주장만 이 항목과 L-code 에 기록한다.",
    "★미검증 주장을 원장에 올리는 것 = 2026-08-08 하루에 9회 검거된 결함 계통(존재를 확립으로 읽기)."),
  parent_of = "WT-D20260808_003 (중립화 라운드 — 이 라운드가 확립한 기전에서 파생, 자가발전 경로)",
  artifacts = "qepm/mailbox/worktask/WT-D20260808_001/ + stage_artifacts/WT_D20260808_001/"
)
q$entries <- E; write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[q] 갱신 완료 (판정 수치 미기록 — 검증 대기)\n")
