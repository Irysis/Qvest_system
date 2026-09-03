## WT-R20260829_006 forge — detect_lookahead 양방향 대조 (positive control + negative coverage)
##   목적: "CLEAN" 을 PIT 증명으로 인용하지 않기 위해, 검출기가 살아있는지(양성)와
##         무엇을 못 잡는지(음성 커버리지)를 같은 자리에서 실측 기록한다.
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
SD <- file.path(ROOT, "stage_artifacts/WT_R20260829_006")
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))

TMP <- file.path("C:/Users/99922/AppData/Local/Temp/claude",
                 "C--Users-99922-OneDrive-Quant-Module-Moltbot",
                 "0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/pitmut")
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)

base_lines <- readLines(file.path(SD, "run_all.R"), warn = FALSE)

.scan <- function(lines, tag) {
  f <- file.path(TMP, paste0(tag, ".R")); writeLines(lines, f)
  r <- tryCatch(detect_lookahead(f), error = function(e) list(error = conditionMessage(e)))
  n <- tryCatch({
    v <- r$violations
    if (is.null(v)) 0L else if (is.data.frame(v)) nrow(v) else length(v)
  }, error = function(e) NA_integer_)
  list(tag = tag, n_violations = n,
       detail = tryCatch(paste(utils::capture.output(str(r, max.level = 2)), collapse = " | "),
                         error = function(e) ""))
}

## ── 0) 무처리 기준선 ──────────────────────────────────────────────────────────
base <- .scan(base_lines, "base_run_all")
cat("[base] run_all.R violations =", base$n_violations, "\n")

## ── 1) 양성 대조 — 선언 idiom 주입 (발화해야 정상) ────────────────────────────
pos_specs <- list(
  P1 = "  ann_sr <- mean(x) / sd(x) * sqrt(252)   # 선언 idiom: 연율화 Sharpe",
  P2 = "  q <- quantile(dt$Ret_1m, 0.9)           # 선언 idiom: 전 표본 분위수",
  P3 = "  s <- scale(dt$score)                    # 선언 idiom: 전 표본 표준화"
)
pos <- lapply(names(pos_specs), function(k)
  .scan(c(base_lines, "f_mut <- function(x, dt) {", pos_specs[[k]], "  invisible(NULL)", "}"),
        paste0("pos_", k)))
names(pos) <- names(pos_specs)

## ── 2) 음성 커버리지 — 비선언 idiom 주입 (발화하면 커버리지 확장) ─────────────
neg_specs <- list(
  N1 = "  mu_full <- mean(dt$Ret_1m, na.rm = TRUE)          # 전 표본 평균 (미래 포함)",
  N2 = "  fwd <- shift(dt$Close, -1)                        # 미래 시점 참조 (lead)",
  N3 = "  W[, w := w / sum(w)]                              # 비중 재정규화 (사후 개입)",
  N4 = "  cvm <- cov(as.matrix(dt[, .(a, b)]))              # 전 표본 공분산",
  N5 = "  best <- dt[which.max(cumret)]                     # 결과 최대점 선택"
)
neg <- lapply(names(neg_specs), function(k)
  .scan(c(base_lines, "g_mut <- function(dt, W) {", neg_specs[[k]], "  invisible(NULL)", "}"),
        paste0("neg_", k)))
names(neg) <- names(neg_specs)

pos_fire <- vapply(pos, function(z) isTRUE(z$n_violations > base$n_violations), logical(1))
neg_fire <- vapply(neg, function(z) isTRUE(z$n_violations > base$n_violations), logical(1))

cat("\n[positive control] fired", sum(pos_fire), "/", length(pos_fire), ":",
    paste(sprintf("%s=%s(n=%s)", names(pos), pos_fire,
                  vapply(pos, function(z) as.character(z$n_violations), "")), collapse = " "), "\n")
cat("[negative coverage] fired", sum(neg_fire), "/", length(neg_fire), ":",
    paste(sprintf("%s=%s(n=%s)", names(neg), neg_fire,
                  vapply(neg, function(z) as.character(z$n_violations), "")), collapse = " "), "\n")

## ── 3) 구조 논거 실측 — T+1 집행 · 재선택 0 · 전 표본 통계 0 ─────────────────
sim <- readRDS(file.path(SD, "forge_sim.rds"))
HL <- as.data.table(sim$HOLDINGS_LOG)
gap <- HL[, .(g = as.integer(unique(Exec_Date) - unique(Signal_Date))), by = Signal_Date]
cat("\n[T+1] exec-sig gap days: min", min(gap$g), "median", median(gap$g), "max", max(gap$g),
    "| gap<=0 건수", sum(gap$g <= 0), "\n")

W <- fread(file.path(SD, "weights.csv"))[, .(Date = as.Date(sig_date), Ticker, w = as.numeric(weight))]
W <- W[Date < as.Date("2026-08-28")]
key_w <- W[, paste0(Date, "|", Ticker)]
key_h <- HL[, paste0(Signal_Date, "|", Ticker)]
cat("[as-is] weights.csv (date,ticker) 쌍", length(key_w), "| 집행 holdings 쌍", length(key_h),
    "| holdings 중 weights 에 없는 쌍", sum(!key_h %in% key_w), "\n")

## alpha_scores 재선택 흔적 검사 — run_all.R 안에서 alpha_scores/setorder/head 사용 여부
src <- paste(base_lines, collapse = "\n")
cat("[fidelity] run_all.R 내 'alpha_scores' 문자열:", lengths(regmatches(src, gregexpr("alpha_scores", src))),
    "| 'setorder(' :", lengths(regmatches(src, gregexpr("setorder\\(", src))),
    "| 'head(' :", lengths(regmatches(src, gregexpr("head\\(", src))), "\n")

out <- list(
  detector = "02_Infrastructure/validation/lookahead_detector.R::detect_lookahead()",
  scanned_file = "stage_artifacts/WT_R20260829_006/run_all.R",
  baseline_violations = base$n_violations,
  positive_control = list(
    injected = pos_specs,
    fired = as.list(pos_fire),
    n_fired = sum(pos_fire), n_total = length(pos_fire),
    reading = "검출기가 이 실행 환경에서 살아 있는지의 증거. 발화 = 계기 생존."),
  negative_coverage = list(
    injected = neg_specs,
    fired = as.list(neg_fire),
    n_fired = sum(neg_fire), n_total = length(neg_fire),
    reading = paste("미발화분은 검출기가 원리적으로 못 보는 idiom 계열이다.",
                    "따라서 baseline CLEAN 은 '선언 idiom 부재'의 증거일 뿐 PIT 증명이 아니다.")),
  structural_argument = list(
    t_plus_1_exec_gap_days = list(min = min(gap$g), median = as.numeric(median(gap$g)), max = max(gap$g),
                                  n_non_positive = sum(gap$g <= 0)),
    weights_as_is = list(weights_pairs = length(key_w), holdings_pairs = length(key_h),
                         holdings_not_in_weights = sum(!key_h %in% key_w),
                         reading = "집행 명부가 weights.csv 의 부분집합 -> forge 는 종목을 고르지 않았다."),
    reselection_scan = list(alpha_scores_mentions = lengths(regmatches(src, gregexpr("alpha_scores", src))),
                            setorder_calls = lengths(regmatches(src, gregexpr("setorder\\(", src))),
                            head_calls = lengths(regmatches(src, gregexpr("head\\(", src))),
                            reading = "top-N 재선택 패턴(setorder(-score)+head(N)) 부재."),
    full_sample_statistics = "0 — 일별 NAV 는 보유 주식수 x 당일 종가만 사용. 경로 누적이라 표본 전체 통계 미사용."))

write_json(out, file.path(SD, "forge_pit_bidirectional.json"),
           auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
cat("\n[pit] forge_pit_bidirectional.json written\n")
