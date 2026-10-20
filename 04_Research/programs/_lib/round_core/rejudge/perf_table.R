## 속도 전후표(round_core/PERF.json) — 손으로 옮겨 적지 않는다(모든 수 = 로그 · 기록 파일에서 읽는다)
##   전(등록 당일) = 구 evaluate.R 최종 판정(단일 프로세스) 벽시계 — 라운드 측정 로그의 '샤드 … 끝' → '종합 판정' 시각
##   전(같은 날) = 구 evaluate.R 격리 사본(legacy_sandbox.R)을 코어 재판정과 같은 날 · 같은 기계에서 돌린 벽시계 — 기계 상태 차이를 빼는 짝
##   후 = 코어 재판정(짝 평가 샤딩 → 병합 · 같은 저장 칸 산출 · 결과 동일 실증과 같은 실행) · 실험(스레드 · 샤드 수 — 같은 결과 대조 포함) · 캐시 · 메모 실증(cache_check.json)
## 사용: Rscript perf_table.R <재판정 출력(timing.jsonl · perf.jsonl)> <cache_check.json | -> <PERF.json> <라운드=결과 디렉터리>... [same_day:<라운드>=<legacy_sandbox 출력 로그>]... [exp:<이름>=<실험 출력 디렉터리>]...
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
a <- commandArgs(trailingOnly = TRUE); OUT <- a[1]; CC <- a[2]; PF <- a[3]; rest <- a[-(1:3)]
kv <- function(x) { i <- regexpr("=", x, fixed = TRUE); c(substr(x, 1, i - 1L), substr(x, i + 1L, nchar(x))) }
pairs <- rest[!grepl("^(same_day|exp):", rest)]
same <- lapply(sub("^same_day:", "", grep("^same_day:", rest, value = TRUE)), kv)
exps <- lapply(sub("^exp:", "", grep("^exp:", rest, value = TRUE)), kv)
base_of <- function(res) {
  L <- unlist(lapply(Sys.glob(file.path(res, "*.log")), function(f) readLines(f, warn = FALSE, encoding = "UTF-8")))
  ts <- function(rx) { z <- grep(rx, L, value = TRUE); if (!length(z)) return(NA) ; as.POSIXct(sub("^== ([0-9-]+ [0-9:]+) .*$", "\\1", z[length(z)]), tz = "Asia/Seoul") }
  s0 <- ts("셀 평가 샤딩 K="); s1 <- ts("샤드 [0-9]+ 개 끝"); s2 <- ts("종합 판정 rc=")
  k <- suppressWarnings(as.integer(sub("^.*셀 평가 샤딩 K=([0-9]+).*$", "\\1", grep("셀 평가 샤딩 K=", L, value = TRUE)[1])))
  list(at = format(s2, "%Y-%m-%d %H:%M"), cell_eval_shards = k, cell_eval_seconds = as.numeric(difftime(s1, s0, units = "secs")),
       final_judgment_seconds = as.numeric(difftime(s2, s1, units = "secs")), final_judgment_mode = "단일 프로세스(구 evaluate.R)",
       source = "results/*.log '셀 평가 샤딩' · '샤드 … 끝' · '종합 판정' 시각")
}
rd_jsonl <- function(f, ...) if (file.exists(f)) lapply(readLines(f, warn = FALSE), fromJSON, ...) else list()
run_of <- function(dir, r) {
  t <- Filter(function(z) identical(z$round, r), rd_jsonl(file.path(dir, "timing.jsonl"))); t <- if (length(t)) t[[length(t)]] else NULL
  st <- Filter(function(z) identical(z$round, r), rd_jsonl(file.path(dir, "perf.jsonl"), simplifyVector = FALSE))
  if (is.null(t)) return(NULL)
  stage <- list(); for (z in st) for (k in names(z$stages)) stage[[k]] <- (stage[[k]] %||% 0) + as.numeric(z$stages[[k]])
  cl <- if (file.exists(file.path(dir, "compare.log"))) readLines(file.path(dir, "compare.log"), warn = FALSE, encoding = "UTF-8") else character(0)
  thr <- unique(unlist(lapply(Filter(function(z) grepl("^shard", z$mode %||% ""), st), function(z) as.character(z$dt_threads %||% "1(샤드 기본값)"))))
  list(mode = sprintf("코어 짝 평가 샤딩 K=%d → 병합", t$K), dt_threads_per_shard = thr,
       shards_seconds = t$shards_seconds, merge_seconds = t$merge_seconds, final_judgment_seconds = t$total_seconds,
       stage_seconds_summed_over_workers = stage, memo = lapply(st, function(z) z$memo),
       same_result = if (length(cl)) all(grepl("구조 차이 0 · 텍스트\\(제외 줄 빼고\\) 동일 TRUE", grep("구조 차이", cl, value = TRUE))) else NA)
}
tm <- rd_jsonl(file.path(OUT, "timing.jsonl"))
rows <- list()
for (p in pairs) {
  x <- kv(p); r <- x[1]
  b <- base_of(x[2]); aft <- run_of(OUT, r)
  sd <- Filter(function(z) identical(z[1], r), same)
  sdb <- if (length(sd)) { L <- readLines(sd[[1]][2], warn = FALSE, encoding = "UTF-8"); z <- grep("^\\[구판 격리\\]", L, value = TRUE)
                           if (length(z)) list(seconds = as.numeric(sub("^.* · ([0-9.]+)초 · .*$", "\\1", z[length(z)])), source = basename(sd[[1]][2]),
                                               mode = "구 evaluate.R 격리 사본(legacy_sandbox.R) · 단일 프로세스 · 코어와 같은 날 · 같은 기계") else NULL } else NULL
  rows[[r]] <- list(before = b, before_same_day = sdb, after = aft,
                    speedup_vs_registration_day = if (!is.null(aft) && is.finite(b$final_judgment_seconds)) round(b$final_judgment_seconds / aft$final_judgment_seconds, 2) else NA,
                    speedup_same_day = if (!is.null(aft) && !is.null(sdb)) round(sdb$seconds / aft$final_judgment_seconds, 2) else NA,
                    result_identity = "rejudge/RESULTS.json")
}
EX <- setNames(lapply(exps, function(e) { r <- Filter(function(z) !is.null(z), lapply(names(rows), function(rr) { v <- run_of(e[2], rr); if (!is.null(v)) c(list(round = rr), v) }))
                                             if (length(r)) r[[1]] else NULL }), vapply(exps, `[`, "", 1))
cc <- if (!identical(CC, "-") && file.exists(CC)) fromJSON(CC, simplifyVector = FALSE) else NULL
P <- list(schema = "round_core_perf_v1", updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
          rule = "결과가 바뀌는 최적화는 쓰지 않는다 — 채택 조건 = 바이트 동일(시각 · 경로 · 평가 시점 지문 제외) · 전후 시간 기록(PERFORMANCE.md)",
          note = "등록 당일 대 오늘은 기계 상태가 다르다(같은 구 코드가 오늘 더 느리다) — 속도 비는 같은 날 짝(speedup_same_day)으로 읽는다",
          final_judgment = rows, experiments = EX,
          measures = list(beta_copy_minimal = "β 짝 사본 = dp_build 가 읽는 파일만(00 · 01 · authoritative_remeasure.json · 05 + 스케일한 02~04) — 저장 패킷과 바이트 대조(RESULTS.json packets_*)",
                          pair_sharding = "최종 판정의 변형별 짝 평가(공통 창 · β 짝 패킷 · 크기 × β · 유동성)를 K 워커로 · 병합 순서 고정 · 엔진 알파 삽입 순서 재현",
                          ta_load_market_memo = "같은 RX0 의 β 짝 사본(같은 보유 종목 · 같은 기간)이 RAWDATA 를 다시 읽지 않는다(프로세스 안 · 계약 함수 그대로)",
                          mc8_cache = "MC8 카드 · 진단 패킷 mc_controls 입력 해시 캐시(placebo_seed 결정론 · run_id · 경로 제외)",
                          raw_disk = "원자료(위생 raw) 비압축 RDS 메모 — 기본 꺼짐(cache_check 시간 · 디스크 비용 기록)"),
          cache_check = cc)
writeLines(toJSON(P, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), PF, useBytes = TRUE)
for (r in names(rows)) with(rows[[r]], cat(sprintf("[PERF] %s — 등록 당일 %.0f초 · 같은 날 구판 %s초 → 코어 %s초(%s) · 같은 날 ×%s\n", r, before$final_judgment_seconds,
                                                   format(before_same_day$seconds %||% NA), format(after$final_judgment_seconds %||% NA), after$mode %||% "-", format(speedup_same_day))))
for (e in names(EX)) if (!is.null(EX[[e]])) cat(sprintf("[PERF 실험] %s — %s %s초 · 스레드 %s · 결과 동일 %s\n", e, EX[[e]]$round, EX[[e]]$final_judgment_seconds,
                                                         paste(EX[[e]]$dt_threads_per_shard, collapse = ","), EX[[e]]$same_result))
