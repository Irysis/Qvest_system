## D10 — package 의 challenge_flags 를 validation 정본과 동기화 (CF9 자기적발 정정 반영)
suppressPackageStartupMessages(library(jsonlite)); source("02_Infrastructure/config.R")
DOUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"
V <- fromJSON(file.path(DOUT, "alpha_validation_depth.json"), simplifyVector = FALSE)
P <- fromJSON(file.path(DOUT, "alpha_package_depth.json"),    simplifyVector = FALSE)
n0 <- length(P$challenge_flags)
P$challenge_flags <- V$challenge_flags
P$diagnostics$primary_basis_invariance <- V$mechanism_timeline$basis_dependence_check$paired_primary_is_basis_invariant
P$patch_log <- list(list(at = format(Sys.time()), by = "d10_sync_package_flags.R",
  what = sprintf("challenge_flags %d→%d 동기화(CF9 자기적발 정정) + diagnostics.primary_basis_invariance 추가",
                 n0, length(V$challenge_flags)),
  unchanged = "hypothesis / factors / verdict / self_pit_check / alpha_vector / diagnostics 기존 필드 불변"))
write_json(P, file.path(DOUT, "alpha_package_depth.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("동기화 완료: challenge_flags %d건\n", length(P$challenge_flags)))
