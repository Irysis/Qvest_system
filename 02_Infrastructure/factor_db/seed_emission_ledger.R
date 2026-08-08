#==============================================================================
# seed_emission_ledger.R — 기존 월별 factor_db parquet 에서 배출 원장 1회 시딩
#
# 목적: emission_guard.R 의 Class R(회귀) 판정은 "직전 관측 빌드에서 났는가"를
#       물으므로 역사가 필요하다. 원장이 비면 첫 빌드들이 전부 "역사 없음"이 되어
#       회귀를 못 본다. 기존 parquet 은 Factor_Name 컬럼만 읽으면 되므로
#       **재빌드가 아니라 읽기**로 역사를 복원할 수 있다.
#
# ★이 스크립트는 factor DB 를 재생성하지 않는다. 읽기 전용.
#
# 사용: Rscript 02_Infrastructure/factor_db/seed_emission_ledger.R [--force]
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow)
})

# 루트 해석 — r-portability ④: 표지 파일 확인으로 고른다(존재가 아니라 정체).
.pick_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd())
  for (c in cands) {
    if (!nzchar(c)) next
    n <- gsub("\\\\", "/", c)
    if (file.exists(file.path(n, "02_Infrastructure/factor_db/factor_db_builder.R"))) return(n)
  }
  stop("[seed_emission_ledger] PROJECT_ROOT 해석 실패 — 표지 파일 없음")
}
ROOT <- .pick_root()
FDB_DIR     <- file.path(ROOT, ".cache", "factor_db")
LEDGER_PATH <- file.path(FDB_DIR, "emission_ledger.csv")

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args

if (file.exists(LEDGER_PATH) && !force) {
  cat(sprintf("[seed] 원장 이미 존재: %s (덮어쓰려면 --force)\n", LEDGER_PATH))
  quit(save = "no", status = 0)
}

files <- sort(list.files(FDB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
if (length(files) == 0L) stop("[seed] 월별 parquet 없음: ", FDB_DIR)
cat(sprintf("[seed] %d개 월 파일 스캔 시작 (Factor_Name 컬럼만 읽음)\n", length(files)))

t0 <- Sys.time()
parts <- vector("list", length(files))
for (i in seq_along(files)) {
  f <- files[i]
  ym <- sub("^factor_db_", "", sub("\\.parquet$", "", basename(f)))
  d <- tryCatch(as.data.table(read_parquet(f, col_select = c("Factor_Name", "Ticker"))),
                error = function(e) NULL)
  if (is.null(d) || nrow(d) == 0L) {
    # ★빈/손상 파일을 "팩터 0개"로 조용히 내려앉히지 않는다 — 표시하고 남긴다.
    cat(sprintf("  [WARN] %s 읽기 실패/빈 파일 — 원장에 read_failed 로 기록\n", basename(f)))
    parts[[i]] <- data.table(ym = ym, Factor_Name = "__READ_FAILED__",
                             n_rows = NA_integer_, n_tickers = NA_integer_)
    next
  }
  parts[[i]] <- d[, .(n_rows = .N, n_tickers = uniqueN(Ticker)), by = Factor_Name][
    , .(ym = ym, Factor_Name, n_rows, n_tickers)]
  if (i %% 50L == 0L) cat(sprintf("  ... %d/%d\n", i, length(files)))
}
ledger <- rbindlist(parts, use.names = TRUE)
ledger[, built_at := "seeded_from_existing_parquet"]
setcolorder(ledger, c("ym", "Factor_Name", "n_rows", "n_tickers", "built_at"))
setorder(ledger, ym, Factor_Name)
fwrite(ledger, LEDGER_PATH)

el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("[seed] 완료: %s\n  %d행 · %d개월 · %d개 팩터 · %.1fs\n",
            LEDGER_PATH, nrow(ledger), uniqueN(ledger$ym), uniqueN(ledger$Factor_Name), el))

# 전 구간 0행(= 한 번도 배출된 적 없음) 팩터 — 이번 라운드의 진단 대상
seen <- ledger[!is.na(n_rows) & n_rows > 0L, unique(Factor_Name)]
cat(sprintf("[seed] 원장에서 1회 이상 배출된 팩터: %d종\n", length(seen)))
