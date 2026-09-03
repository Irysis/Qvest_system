# detect_lookahead 양방향 대조 — WT-R20260829_007 forge
#   ①양성 대조: **R 방언 선언 idiom** 주입 -> 발화해야 한다 (검출기가 살아있다는 증거)
#   ②커버리지 반증: 비선언 idiom(실제 look-ahead) 주입 -> 발화 여부 실측
# ★1차 시도 기록: Python 방언 idiom(.shift(-1) 등)을 양성 대조로 썼더니 0/3 미발화였다.
#   R 스캔 분기와 PY_* 분기는 패턴 집합이 분리돼 있다(is_python 로 dispatch).
#   즉 "양성 대조를 축에 맞춰 옮기지 않으면 검사기 죽음이 통과로 보인다".
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages(library(jsonlite))
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))

STAGE <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
TMP   <- file.path(STAGE, ".pitprobe"); dir.create(TMP, showWarnings = FALSE)
BASE  <- readLines(file.path(STAGE, "run_all.R"), warn = FALSE)

.run <- function(lines, tag) {
  f <- file.path(TMP, sprintf("probe_%s.R", tag))
  writeLines(lines, f)
  r <- detect_lookahead(f, verbose = FALSE)
  n <- as.integer(r$n_violations %||% length(r$violations))
  codes <- if (n > 0) unique(vapply(r$violations, function(v) v$check, "")) else character(0)
  list(tag = tag, scanned = isTRUE(r$scanned) || !is.na(r$clean),
       clean = r$clean, violations = n, fired = n > 0, codes = codes)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# 주입 지점 = 결정경로 루프 안 (.replay 본문, 비중 소비 직전)
anchor <- grep("^    tw <- W\\[Date == sd_i, \\.\\(Ticker, w\\)\\]", BASE)
stopifnot(length(anchor) == 1L)
ins <- function(code) append(BASE, code, after = anchor - 1L)

res <- list()
res[["A0_baseline"]] <- .run(BASE, "A0_baseline")

#--- ① 양성 대조 — R 방언 선언 idiom (발화해야 정상) ----------------------
res[["B1_C7a_scale_signal"]] <- .run(ins(
  '    Score_z <- scale(sigvec)   # signal weight factor'),
  "B1_C7a_scale_signal")

res[["B2_C7b_rank_fwd_ret"]] <- .run(ins(
  '    .sel <- order(fwd_ret_1m, decreasing = TRUE)[1:25]'),
  "B2_C7b_rank_fwd_ret")

res[["B3_C15_direct_parquet"]] <- .run(ins(
  '    .fd <- arrow::read_parquet("06_Registry/factor_db/factor_db_202501.parquet")'),
  "B3_C15_direct_parquet")

res[["B4_C13_negate"]] <- .run(ins(
  '    NEGATE_FACTORS <- c("VOL", "SIZE")'),
  "B4_C13_negate")

res[["B5_C12_best_sharpe"]] <- .run(ins(
  '    if (sr > best_sharpe) best_sharpe <- sr'),
  "B5_C12_best_sharpe")

#--- ② 커버리지 반증 — 비선언 idiom (전부 실제 look-ahead) ---------------
# C1: R 음수 shift = 미래행 당김. PY_C7_NEG_SHIFT 는 .py 전용이고 R 분기엔 대응 패턴이 없다.
res[["C1_R_negative_shift"]] <- .run(ins(
  '    fut <- RAWDATA[, .(f = shift(Close, -1L)), by = Ticker]'),
  "C1_R_negative_shift")

# C2: 전 표본 공분산을 결정경로에서 인스턴스화
res[["C2_fullsample_cov"]] <- .run(ins(c(
  '    Sfull <- stats::cov(matrix(RAWDATA$Close[1:1000], ncol = 4L))',
  '    tilt  <- 1 / diag(Sfull)')),
  "C2_fullsample_cov")

# C3: 전 표본 평균으로 비중 재정규화 (pure-function 위반 + full-sample 통계)
res[["C3_fullsample_mean_renorm"]] <- .run(ins(c(
  '    gmu <- base::mean(RAWDATA$Close, na.rm = TRUE)',
  '    wadj <- W[Date == sd_i, w] * (gmu / gmu)')),
  "C3_fullsample_mean_renorm")

# C4: 미래 거래일 종가를 수동 인덱싱으로 당겨 선별에 사용
res[["C4_manual_future_index"]] <- .run(ins(c(
  '    nxt <- all_dates[which(all_dates == exec_date) + 1L]',
  '    fpx <- RAWDATA[Date == nxt, .(Ticker, Close)]',
  '    tw2 <- merge(W[Date == sd_i], fpx, by = "Ticker")')),
  "C4_manual_future_index")

pos <- c("B1_C7a_scale_signal","B2_C7b_rank_fwd_ret","B3_C15_direct_parquet",
         "B4_C13_negate","B5_C12_best_sharpe")
cov_ <- c("C1_R_negative_shift","C2_fullsample_cov","C3_fullsample_mean_renorm",
          "C4_manual_future_index")

out <- list(
  wt_id = "WT-R20260829_007",
  purpose = "detect_lookahead 양방향 대조 — 양성 대조(R 방언 선언 idiom) + 커버리지 반증(비선언 idiom)",
  detector = "02_Infrastructure/validation/lookahead_detector.R::detect_lookahead",
  target   = "stage_artifacts/WT_R20260829_007/run_all.R",
  baseline_clean = res$A0_baseline$clean,
  baseline_violations = res$A0_baseline$violations,
  probes   = res,
  positive_control_fired = sum(vapply(res[pos],  function(x) x$fired, TRUE)),
  positive_control_n     = length(pos),
  coverage_probe_fired   = sum(vapply(res[cov_], function(x) x$fired, TRUE)),
  coverage_probe_n       = length(cov_),
  dialect_split_record = paste(
    "1차 시도에서 Python 방언 idiom(.shift(-1) / merge_asof forward)을 양성 대조로 주입했으나 0/3 미발화.",
    "detect_lookahead 는 is_python 로 분기하며 PY_* 패턴은 .py 파일에만 적용된다.",
    "R 분기에는 **음수 shift 대응 패턴이 아예 없다** — 아래 C1 이 그 직접 실증이다."),
  interpretation = NA
)
out$interpretation <- sprintf(
  "양성 대조 %d/%d 발화 -> 검출기는 살아있다. 커버리지 반증 %d/%d 발화 -> CLEAN 은 '선언 idiom 부재'의 증거일 뿐이며 PIT 증명이 아니다.",
  out$positive_control_fired, out$positive_control_n,
  out$coverage_probe_fired, out$coverage_probe_n)

writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null"),
           file.path(STAGE, "forge_pit_bidirectional.json"))
for (nm in names(res)) cat(sprintf("  %-28s fired=%-5s n=%d codes=%s\n", nm, res[[nm]]$fired,
                                   res[[nm]]$violations, paste(res[[nm]]$codes, collapse = ",")))
cat(sprintf("positive_control fired %d/%d | coverage_probe fired %d/%d\n",
            out$positive_control_fired, out$positive_control_n,
            out$coverage_probe_fired, out$coverage_probe_n))
unlink(TMP, recursive = TRUE)
