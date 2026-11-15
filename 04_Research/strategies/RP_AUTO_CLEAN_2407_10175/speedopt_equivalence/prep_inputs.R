# =============================================================================
# prep_inputs.R — 등가 시험 입력 만들기 (엔진 속도 최적화 · LANE-SPEEDOPT-2407-20261115)
#
# 하는 일: 레인 검증기가 엔진에 넣는 입력을 그대로 만든다.
#   run_paper_replication.R 의 1(load_rawdata = .cache/RAWDATA.parquet · benchmark.parquet 를 read_parquet → data.table) ·
#   1-c(활성 epoch 의 측정 축 주입 ma_inject_universe) 와 같은 호출 — data_cutoff 는 레인이 넘기지 않으므로 없음.
#   그 뒤 엔진이 실제로 읽는 열만 남긴다(행 수 · 행 순서 그대로): RAWDATA = Date · Ticker · Ret · Size · K200 · KQ150 · K200_IDX
#   (engine.R .NEED + .IDXCOL) · BM_DT = 전체(작다). 엔진 산출은 이 열들의 함수라 결과가 같고, 시험 프로세스 메모리만 줄어든다.
# 사용: Rscript prep_inputs.R <out.rds>
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
args <- commandArgs(TRUE)
if (length(args) < 1L) stop("usage: Rscript prep_inputs.R <out.rds>")
OUT <- gsub("\\\\", "/", args[1])

# 루트 = 이 스크립트 위치의 다섯 단계 위(시험 러너 self-first · r-portability ④-b · 절대 경로로 부른다) — 표지 파일로 검증 · 경로 정규화 함수는 쓰지 않는다
.self <- gsub("\\\\", "/", sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
ROOT <- dirname(dirname(dirname(dirname(dirname(.self)))))
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py")))
  stop("[prep] 루트 표지 없음(스크립트를 절대 경로로 불러라): ", ROOT)
cat(sprintf("[prep] root %s\n", ROOT))

raw_p <- file.path(ROOT, ".cache", "RAWDATA.parquet")
bm_p  <- file.path(ROOT, ".cache", "benchmark.parquet")
t0 <- proc.time()[[3L]]
RAWDATA <- as.data.table(read_parquet(raw_p))
BM_DT   <- as.data.table(read_parquet(bm_p))
if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
cat(sprintf("[prep] RAWDATA %d rows %s ~ %s · BM %d rows (%.0fs)\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date),
            nrow(BM_DT), proc.time()[[3L]] - t0))

source(file.path(ROOT, "02_Infrastructure", "contracts", "measurement_axis.R"))
ep_act <- ma_epoch(root = ROOT)                         # run_paper_replication: universe · start_date 미지정 = 활성 epoch
stopifnot(identical(ep_act$universe, "ALL_HYG"))
ep <- ma_epoch_by_universe("ALL_HYG", root = ROOT)     # run_paper_replication 1-c 와 같은 호출
inj <- ma_inject_universe(RAWDATA, ep)
RAWDATA <- inj$RAWDATA
cat(sprintf("[prep] axis %s injected · members/day median %s · start %s (%.0fs)\n", ep$id,
            format(inj$diag$members_per_day_median), format(ep_act$start_date), proc.time()[[3L]] - t0))

keep <- c("Date", "Ticker", "Ret", "Size", "K200", "KQ150", "K200_IDX")
stopifnot(all(keep %in% names(RAWDATA)))
RED <- RAWDATA[, ..keep]
rm(RAWDATA); invisible(gc())
meta <- list(raw_parquet = raw_p, raw_md5 = unname(tools::md5sum(raw_p)), raw_mtime = format(file.mtime(raw_p)),
             bm_parquet = bm_p, bm_md5 = unname(tools::md5sum(bm_p)), bm_mtime = format(file.mtime(bm_p)),
             epoch = ep$id, start_date = format(ep_act$start_date), rows = nrow(RED), columns = keep,
             built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
saveRDS(list(RAWDATA = RED, BM_DT = BM_DT, start_date = as.Date(ep_act$start_date), meta = meta), OUT, compress = FALSE)
cat(sprintf("[prep] saved %s (%.0fs)\n", OUT, proc.time()[[3L]] - t0))
writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE), sub("\\.rds$", "_meta.json", OUT))
