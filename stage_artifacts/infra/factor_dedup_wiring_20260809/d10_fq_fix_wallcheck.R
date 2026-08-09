#==============================================================================
# d10_fq_fix_wallcheck.R — FQ-218 wall_check 의 자기참조 오기 정정
# 원문이 "수리하면 FQ-218 이 만든 alias 선언이 무효" 라고 썼는데, alias 선언을
# 만든 것은 FQ-218(수리 과제 자신)이 아니라 이 라운드의 registry 갱신이다.
# 원장에 틀린 인과를 남기지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-218")
if (length(i) != 1L) stop("[d10] FQ-218 을 찾지 못함")

cat("[d10] 이전:\n  ", Q$entries[[i]]$wall_check, "\n")
Q$entries[[i]]$wall_check <- paste(
  "미측정. 수리 후 canonical_screen_bt 로 PORT_t 실측 필요.",
  "★수리하면 2026-08-09 registry 갱신이 등재한 alias 선언(C10_SUE_Persistence ->",
  "C01_SUE, C13_Revision_Breadth_3m -> C04_ESBR)이 **무효**가 된다 — 그 선언은",
  "'정보가 같다'가 아니라 '현 빌드에서 값이 같다'는 조건부 선언이며,",
  "factor_registry.json 의 해당 dedup.defect.revisit_on 필드가 조건을 명시한다.",
  "창 수리 후 재측정하여 재선언할 것.")
write_frontier_queue(Q)

Q2 <- read_frontier_queue()
i2 <- which(vapply(Q2$entries, function(e) as.character(e$id)[1], character(1)) == "FQ-218")
cat("[d10] 이후:\n  ", Q2$entries[[i2]]$wall_check, "\n")
cat(sprintf("[d10] 총 항목 %d (변동 없어야 정상)\n", length(Q2$entries)))
