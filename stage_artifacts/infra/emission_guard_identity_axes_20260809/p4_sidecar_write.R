## P4 — 사이드카 기록 경로 확인
##   factor_emission_guard 는 rep 을 write_json 으로 쓴다. 이제 rep$identity 안에
##   data.table 3개가 중첩된다. 직렬화가 깨지면 래퍼의 tryCatch 가 삼켜서
##   **경고도 사이드카도 없이** 조용히 사라진다 — 그 경로를 실제로 밟아 본다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
say <- function(fmt, ...) cat(sprintf(paste0("[p4] ", fmt, "\n"), ...))
suppressMessages(source("02_Infrastructure/factor_db/emission_guard.R"))

tmpd <- file.path(tempdir(), "p4_emission_sidecar")
unlink(tmpd, recursive = TRUE); dir.create(tmpd, recursive = TRUE)

tk <- sprintf("A%05d", 1:80)
set.seed(9)
live <- rbindlist(lapply(paste0("SYN", sprintf("%02d", 1:15)), function(f)
  data.table(Ticker = tk, Factor_Name = f, Raw_Value = rnorm(80),
             Z_Score = rnorm(80), Coverage = TRUE)))
# 중복 1쌍 + 죽은 배출 1종 + 동률 1종을 심어 세 축이 전부 채워진 상태로 직렬화한다
dup  <- copy(live[Factor_Name == "SYN01"])[, Factor_Name := "SYN01_CLONE"]
dead <- data.table(Ticker = tk, Factor_Name = "SYN_DEAD", Raw_Value = 1.0,
                   Z_Score = NA_real_, Coverage = FALSE)
tie  <- data.table(Ticker = tk, Factor_Name = "SYN_TIE", Raw_Value = 0,
                   Z_Score = 0, Coverage = TRUE)
res <- rbindlist(list(live, dup, dead, tie), use.names = TRUE)

r <- suppressWarnings(factor_emission_guard(
  result = res, ym = "209901", fdb_dir = tmpd,
  registry_path = "02_Infrastructure/factor_db/factor_registry.json",
  write_artifacts = TRUE,
  identity_baseline_path = "02_Infrastructure/factor_db/emission_declared_identity.json"))

sc <- file.path(tmpd, "emission_report_209901.json")
if (!file.exists(sc)) {
  say("★사이드카 미생성 — 직렬화 경로가 죽었다")
} else {
  j <- fromJSON(sc, simplifyVector = FALSE)
  say("사이드카 %s (%.1f KB)", basename(sc), file.size(sc) / 1024)
  say("  identity 키 존재: %s · verdict %s", !is.null(j$identity), j$identity$verdict)
  say("  축 D dead: %s", paste(unlist(j$identity$axis_D$dead), collapse = ","))
  say("  축 T warn: %s", paste(unlist(j$identity$axis_T$tie_warn), collapse = ","))
  say("  축 I 미선언 쌍 수: %d", length(j$identity$axis_I$undeclared))
  say("  왕복 후에도 경고 %d건 보존: %s", length(j$identity$warnings),
      substr(paste(unlist(j$identity$warnings), collapse = " | "), 1, 200))
}
say("원장 append 정상: %s", file.exists(file.path(tmpd, "emission_ledger.csv")))
unlink(tmpd, recursive = TRUE)
