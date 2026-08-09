## S9 — 최종 확인: 등재 생존 + 산출물 실재 (병렬 세션 덮어쓰기 검거)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")
FQ <- readLines("stage_artifacts/infra/factor_emission_identity_20260809/FQ_ID.txt")[1]
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
cat("[s9] 큐 항목:", length(Q$entries), "·", FQ, "생존:", FQ %in% ids, "\n")
stopifnot(FQ %in% ids)
e <- Q$entries[[which(ids == FQ)]]
cat("[s9] status:", e$status, "· lane:", e$lane, "· created:", e$created, "\n")
cat("[s9] source_refs:", length(e$source_refs), "· consumer_surfaces:", length(e$consumer_surfaces), "\n")

D <- "stage_artifacts/infra/factor_emission_identity_20260809"
f <- sort(list.files(D))
cat("[s9] 산출물", length(f), "개:\n")
for (x in f) cat(sprintf("   %-38s %8.0f B\n", x, file.info(file.path(D, x))$size))
rep <- "04_Research/01_reports/factor_emission_identity_audit_20260809.md"
cat("[s9] 보고서 존재:", file.exists(rep), "·", file.info(rep)$size, "B\n")
cat("[s9] 완료\n")
