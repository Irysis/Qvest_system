## 03_export_frame.R — 단계 2 앞부분: 파이썬 단계(단말 계층 · 생성기 · 잠재 모형)가 쓸 공통 틀과 기존 팩터 특성을 내보낸다.
##   ① 틀 = 측정기(aif_market)와 같은 것: 거래일 · 종목 · 월말 신호일 · 보유월 범위 · 유니버스 멤버 표 · 앞으로의 수익(1 · 3 · 6 · 12개월) · 일별 수익
##      → 파이썬이 다른 날짜 · 종목 순서나 다른 유니버스 판정을 쓰지 않게 한다(유니버스 판정식은 인프라 측정 축 계약 하나뿐이다).
##   ② 기존 팩터 = 결합용 뷰 접근자 fc_load_month(direction = "registry", tickers = 그 달 멤버, missing = "na", dedup = TRUE)
##      → 달마다 parquet 한 개(멤버 안에서 다시 매긴 순위 [−1, 1] · 별칭 접힘). 저장 파일을 직접 읽지 않는다.
##   실행: Rscript run/03_export_frame.R   (감시 셸 ops/aif_run.py 가 띄운다 · 달 하나 = 체크포인트 하나)
##   이진 파일 배치: 행 우선(신호 또는 거래일 × 종목) · 실수 = float32(결측 = NaN) · 멤버 표 = uint8.
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_status.R")) source(file.path(D, "R", f))
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
PART <- c(0, 0.30)                                   # 이 실행이 맡는 단계 진행 구간(나머지 = 파이썬 단말 적재)
M <- aif_market(root, cfg); ns <- length(M$sig_dates); nt <- length(M$tickers); nd <- length(M$dates)
FR <- aif_out("frame", root = root, cfg = cfg); dir.create(FR, recursive = TRUE, showWarnings = FALSE)
aif_stage_begin("terminals", unit_total = ns + 1L, unit_name = "달", part_from = PART[1], part_to = PART[2], threads = cfg$resources$jobs$terminals$threads, root = root, cfg = cfg)

## ① 틀
wbin <- function(x, name, what = c("f32", "u8")) {            # 행렬은 행 우선으로 푼다
  what <- match.arg(what); v <- if (is.matrix(x)) as.vector(t(x)) else as.vector(x)
  aif_write_atomic(file.path(FR, name), function(p) { con <- file(p, "wb"); on.exit(close(con))
    if (what == "u8") writeBin(as.raw(v), con) else writeBin(as.numeric(v), con, size = 4L) })
}
tag <- M$source$tag; fj <- file.path(FR, "frame.json")
if (file.exists(fj) && identical(fromJSON(fj)$rawdata_tag, tag)) aif_log("틀 — 이미 내보냄(건너뜀)") else {
  fwrite(data.table(i = seq_len(nd) - 1L, Date = format(M$dates)), file.path(FR, "dates.csv"))
  fwrite(data.table(j = seq_len(nt) - 1L, Ticker = M$tickers), file.path(FR, "tickers.csv"))
  fwrite(data.table(s = seq_len(ns) - 1L, sig_date = format(M$sig_dates), sig_idx = M$sig_idx - 1L, hold_a = M$hold_rng[, "a"] - 1L, hold_b = M$hold_rng[, "b"] - 1L,
                    hold_ok = as.integer(M$hold_ok), n_members = rowSums(M$MEM)), file.path(FR, "signals.csv"))
  wbin(M$MEM, "mem.u8", "u8")
  for (h in names(M$FWD)) wbin(M$FWD[[h]], sprintf("fwd_%s.f32", h))
  wbin(M$R0, "ret_daily.f32"); wbin(M$bm, "bm_daily.f32"); wbin(M$rf, "rf_daily.f32")
  aif_write_json(list(built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), rawdata_tag = tag, universe = M$ep, n_days = nd, n_tickers = nt, n_signals = ns,
                      last_hold_end = format(M$last_hold_end), horizons_m = as.integer(names(M$FWD)), layout = "row-major", float = "float32 little-endian · NaN = 결측",
                      files = list(mem = "mem.u8 [n_signals × n_tickers]", fwd = "fwd_<h>.f32 [n_signals × n_tickers]", ret_daily = "ret_daily.f32 [n_days × n_tickers] · 행 없는 날 = 0",
                                   bm_daily = "bm_daily.f32 [n_days]", rf_daily = "rf_daily.f32 [n_days]")), fj)
  aif_log("틀 내보냄 — 거래일 %d · 종목 %d · 신호 %d", nd, nt, ns)
}
aif_stage_unit(1L, "공통 틀", root = root, cfg = cfg)

## ② 기존 팩터(결합용 뷰 · 등록부 방향 · 멤버 안 순위)
invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure", "factor_db", "factor_combinable.R")))))   # 함수만 싣는다(접근자 · 별칭 접기는 그 안에서 한 번만 적재)
FC <- file.path(FR, "fc"); dir.create(FC, recursive = TRUE, showWarnings = FALSE)
skipped <- list(); nfac <- integer(0)
for (s in seq_len(ns)) {
  sd <- M$sig_dates[s]; p <- file.path(FC, sprintf("fc_%s.parquet", format(sd, "%Y%m")))
  if (!file.exists(p)) {
    r <- tryCatch({ x <- NULL; invisible(capture.output(x <- fc_load_month(sd, direction = "registry", tickers = M$tickers[M$MEM[s, ]], missing = "na", dedup = TRUE, family = FALSE, root = root))); x },
                  error = function(e) { skipped[[format(sd)]] <<- conditionMessage(e); NULL })
    if (!is.null(r) && nrow(r$panel)) {
      W <- r$panel; fc <- setdiff(names(W), "Ticker")
      sch <- do.call(schema, c(list(Ticker = utf8()), setNames(rep(list(float32()), length(fc)), fc)))
      aif_write_atomic(p, function(q) write_parquet(arrow_table(W, schema = sch), q))
      nfac <- c(nfac, length(fc))
    }
  }
  if (s %% 12L == 0L || s == ns) aif_stage_unit(1L + s, sprintf("%s 까지 기존 팩터 내보냄", format(sd, "%Y-%m")), root = root, cfg = cfg)
}
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), months = length(Sys.glob(file.path(FC, "fc_*.parquet"))), skipped = skipped,
                    direction = "registry", rerank = "그 달 유니버스 멤버 안에서 다시 순위", missing = "na", dedup = TRUE), file.path(FC, "export.json"))
aif_stage_end(done = FALSE, root = root, cfg = cfg)
aif_log("기존 팩터 내보냄 — 달 %d · 건너뛴 달 %d%s", length(Sys.glob(file.path(FC, "fc_*.parquet"))), length(skipped),
        if (length(nfac)) sprintf(" · 이번 실행 팩터 수 %d~%d", min(nfac), max(nfac)) else "")
