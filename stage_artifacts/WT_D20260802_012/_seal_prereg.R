## _seal_prereg.R — 사전등록 파일 바이트 봉인 (측정 개시 전 1회, overwrite 거부)
suppressPackageStartupMessages({library(jsonlite); library(digest)})
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
PP <- file.path(OUT, "preregistration.json"); SP <- file.path(OUT, "preregistration.seal.json")
stopifnot(file.exists(PP)); if (file.exists(SP)) stop("seal 이미 존재 — overwrite 거부")
fh <- digest::digest(file = PP, algo = "sha256")
ch <- fromJSON(PP)$config_hash
write_json(list(file = "preregistration.json", file_sha256 = fh, config_hash = ch,
                sealed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                note = "측정 개시 전 봉인. run_r43 이 이 해시로 사전등록 불변을 검증한다."),
           SP, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[seal] file_sha256=%s config_hash=%s\n", fh, ch))
