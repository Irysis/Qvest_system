## 강화 entry 데이터 컷오프·빈티지 지문 — reinforce_ledger.R::rf_open_entry (2026-09-24 · 플랜 P0-07 · 감사 D4-11·D8-03 ·
##   수리 2026-09-25 적대검증 F1 — 지문 scheme pin_fp_v2: 소비자 코드에서 재도출한 소비 열의 행 키 정렬 바이트 해시)
## 실사고: 한 entry 의 칸이 서로 다른 데이터 종료일에서 측정됐고(00_manifest end_date 혼재 — 감사 6개 · 09-24 8개), 승격은 부모 저장값
##   (다른 판본 — 09-18 벤치 축 이관 전)과 자식 칸을 비교했다. entry 가 자기 판본을 모르면 이 교락은 사후 포렌식으로만 보인다.
## 이 검사가 재는 것 (합성 픽스처 · 운영 원장·저널 무접촉 — 원장 사본은 읽기만):
##   B. rf_open_entry — data_cutoff(직전 완결 월말 · 데이터로 증명)·data_fingerprint(= 독립 계산 digest) 기록 ·
##      승격 자식 대조: 같은 판본 match · 과거 행 개정 mismatch(history_revised · 부분·연도·열) + jlog 'vintage_mismatch' ·
##      ★F1: 셀 엔진 소비 열 Vol 1바이트 개정 · Size 값 교환(합 보존) → mismatch · 비소비 열(High) 개정 → match(저널 없음) ·
##      엔진(engine_path)이 읽는 열도 지문에 · 자식 열이 부모와 달라도 부모 열로 재측정해 대조 가능 ·
##      자식 창 전진 mismatch(cutoff_changed · history 는 부모 cutoff 재계산으로 match) · cutoff 지정 재현 match ·
##      부모 지문 부재 → unknown + jlog 'vintage_unverified' · 끄개(QVEST_RF_VINTAGE=0) · 데이터 부재 = 개설은 된다 ·
##      기존 필드 불변 · 재사용 경로 무계산 · 계산 중 외부 writer 보존(재적재)
##      — 돌연변이: 개정 무시 · 부모 cutoff 재계산 제거 · 부모 열 대신 자식 열로 재측정 · 엔진 경로 미전달 · 재적재 제거 → 각각 red
##   B8. F2(2차 적대검증) — 엔진이 직접 읽는 패널(지문 밖 소비 원천)이 있으면 해시가 같아도 승격 대조 = unknown + jlog vintage_unverified ·
##      부모 열 재측정본에도 원천 범위 전달 · 음성 대조(엔진이 안 읽으면 match) — 돌연변이 2종(unverified 무시 · 재측정본 미전달) red
##   D. rf_entry_end_dates — 합성 원장(혼재/단일/WT dict/산출물 결손) 양성·음성 · 돌연변이(첫 칸만 읽기) red ·
##      운영 원장 **사본**에서 감사 6 entry(0-기준 16·23·32·45·47·57) 재현(산출물 결손이면 SKIP)
suppressMessages({ library(jsonlite); library(data.table); library(arrow) })
CODE <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")   # 검사 대상 코드 루트(읽기만)
P <- 0L; FL <- 0L; SK <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { FL <<- FL + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
sk <- function(m) { SK <<- SK + 1L; cat(sprintf("  SKIP %s\n", m)) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
LEDGER <- file.path(CODE, "02_Infrastructure/reinforcement/reinforce_ledger.R")
PIN    <- file.path(CODE, "02_Infrastructure/data/pin_cache.R")
BASE   <- { b <- tempdir(); if (nchar(b) > 120L) { b <- "C:/tmp"; dir.create(b, showWarnings = FALSE) }; b }
JL <- file.path(BASE, sprintf("rfdv_jlog_%d.jsonl", Sys.getpid())); unlink(JL)
.old_env <- Sys.getenv(c("QVEST_RP_JLOG", "QVEST_RF_VINTAGE"), unset = NA)
Sys.setenv(QVEST_RP_JLOG = JL); Sys.unsetenv("QVEST_RF_VINTAGE")

## 원장 적재(전용 env) — 텍스트 치환 돌연변이도 같은 경로
load_ledger <- function(txt = NULL) {
  env <- new.env(parent = globalenv())
  if (is.null(txt)) sys.source(LEDGER, envir = env, keep.source = FALSE)
  else eval(parse(text = txt, keep.source = FALSE, encoding = "UTF-8"), envir = env)
  env
}
LSRC <- readLines(LEDGER, encoding = "UTF-8", warn = FALSE)
FP <- local({
  ex <- parse(PIN, encoding = "UTF-8", keep.source = FALSE); env <- new.env(parent = baseenv())
  for (e in as.list(ex)) if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) &&
                             grepl("^(pin_fingerprint|pin_complete_month_end|pin_fp_|\\.pin_fp_)", as.character(e[[2]]))) eval(e, env)
  env
})
jl_events <- function() if (file.exists(JL)) vapply(readLines(JL, warn = FALSE), function(l) fromJSON(l)$event %||% "", character(1), USE.NAMES = FALSE) else character(0)
jl_last <- function(ev) { if (!file.exists(JL)) return(NULL); L <- Filter(function(x) identical(x$event, ev), lapply(readLines(JL, warn = FALSE), fromJSON)); if (length(L)) L[[length(L)]] else NULL }

## 합성 데이터(영업일 × 종목) — 한 번 만들고 잘라 쓴다. 소비 열(Close·Ret·K200·KQ150·Vol·Size) + 비소비 열(High)
mk <- function(end = as.Date("2008-12-31"), n_tk = 12L) {
  set.seed(5); days <- seq(as.Date("2004-01-02"), end, by = "day"); days <- days[!format(days, "%u") %in% c("6", "7")]
  R <- CJ(Ticker = sprintf("T%02d", seq_len(n_tk)), Date = days)
  R[, Ret := round(rnorm(.N, 2e-4, 0.02), 6)][, Close := round(1e4 * cumprod(1 + Ret), 2), by = Ticker]
  R[, `:=`(K200 = 1, KQ150 = 0, Vol = round(1e5 * runif(.N, 0.5, 1.5)), Size = round(1e11 * runif(.N, 0.5, 1.5)),
           High = round(Close * 1.01, 2))]; setorder(R, Date, Ticker)
  B <- R[, .(BM_Ret = round(mean(Ret), 8)), by = Date][, BM_Close := round(1000 * cumprod(1 + BM_Ret), 4)][, BM_Src := "fx"]
  list(R = R[], B = B[])
}
FULL <- mk()
put <- function(root, end, modify = NULL) {
  dir.create(file.path(root, ".cache"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  R <- copy(FULL$R[Date <= end]); B <- FULL$B[Date <= end]
  if (!is.null(modify)) modify(R)
  arrow::write_parquet(R, file.path(root, ".cache", "RAWDATA.parquet"))
  arrow::write_parquet(B, file.path(root, ".cache", "benchmark.parquet"))
}
flip1 <- function(x) { b <- writeBin(as.double(x), raw(), size = 8L, endian = "little"); b[1] <- xor(b[1], as.raw(1L))
  readBin(b, "double", n = 1L, size = 8L, endian = "little") }
entry_of <- function(L, root, bid) Filter(function(e) identical(e$base_id, bid), L$rf_load(1L, root)$entries)[[1]]
ul <- function(x) as.character(unlist(x))

cat("=== B. rf_open_entry 빈티지 (합성 샌드박스 원장) ===\n")
T1 <- file.path(BASE, sprintf("rfdv_%d_a", Sys.getpid())); unlink(T1, recursive = TRUE)
put(T1, as.Date("2008-09-30"))
L <- load_ledger()
chk(all(c("rf_entry_end_dates", ".rf_entry_vintage", ".rf_pin_fp_env") %in% ls(L, all.names = TRUE)) &&
      "data_cutoff" %in% names(formals(L$rf_open_entry)) && "engine_path" %in% names(formals(L$.rf_entry_vintage)),
    "B0 원장에 P0-07 계기(rf_entry_end_dates · 빈티지(engine_path) · data_cutoff 인자)")
invisible(capture.output(L$rf_open_entry(1L, "RP_V1", "C", paper_key = "fx", root = T1)))
e1 <- entry_of(L, T1, "RP_V1")
ind <- FP$pin_fingerprint("2008-08-31", root = T1, code_root = c(T1, CODE))
chk(identical(e1$data_cutoff, "2008-08-31"), "B1a data_cutoff = 직전 완결 월말(데이터 최대 09-30 → 08-31)", as.character(e1$data_cutoff %||% "NULL"))
chk(identical(e1$data_fingerprint$status, "ok") && identical(e1$data_fingerprint$digest, ind$digest) &&
      identical(e1$data_fingerprint$scheme, "pin_fp_v2"),
    "B1b data_fingerprint(pin_fp_v2) = 파일에서 독립 계산한 지문(digest 일치)", paste(e1$data_fingerprint$digest, ind$digest))
chk(all(c("Vol", "Size", "Close", "Ret") %in% ul(e1$data_fingerprint$raw$cols)) && !("High" %in% ul(e1$data_fingerprint$raw$cols)) &&
      length(ul(e1$data_fingerprint$consumers$files)) >= 3L,
    "B1b2 entry 지문 = 소비 열(Vol·Size 포함 · 비소비 High 제외) + 소비자 파일 기록", paste(ul(e1$data_fingerprint$raw$cols), collapse = ","))
old_keys <- c("base_id", "base_grade", "paper_key", "paper_id", "base_artifacts", "engine_path", "status", "target_grade",
              "measurement_axis", "axis_valid", "attempts_used", "attempts", "judge", "opened_at")
## ★P1-08(HUMAN 레인 규칙 · 10-03 최종 통합 INTEG-TF): 개설 entry 에 레인 필드(priority · experiment — rf_open_entry 가 붙인다)가 생긴다.
##   빈티지와 무관한 다른 갈래 필드라 빼고 같은 단정(기존 필드 순서 불변 · 빈티지 새 필드 2개 · 그 밖 새 필드 0)을 유지한다.
.lane_keys <- c("priority", "experiment")
chk(identical(setdiff(names(e1), c("data_cutoff", "data_fingerprint", .lane_keys)), old_keys) && is.null(e1$data_vintage_vs_parent),
    "B1c 기존 필드·순서 불변 + 새 필드 2개만(부모 없으면 대조 필드 없음 · P1-08 레인 필드 제외)", paste(names(e1), collapse = ","))
chk(!any(grepl("^vintage", jl_events())), "B1d 부모 없는 개설 — 빈티지 저널 0")
invisible(capture.output(r2 <- L$rf_open_entry(1L, "RP_V1", "C", root = T1)))
chk(identical(r2$data_fingerprint$digest, e1$data_fingerprint$digest) && length(L$rf_load(1L, T1)$entries) == 1L,
    "B1e 기존 entry 재사용 — 새로 쓰지 않고 그대로 반환")

promo <- function(L, root, bid, parent = "RP_V1", ...) {
  invisible(capture.output(L$rf_open_entry(1L, bid, "B", parent = list(base_id = parent, depth = 1L, cell = "B1_1"),
                                           count_paper = FALSE, root = root, ...)))
  entry_of(L, root, bid)
}
p1 <- promo(L, T1, "RP_V1_promo1")
chk(identical(p1$data_vintage_vs_parent$status, "match") && identical(p1$data_vintage_vs_parent$history, "match") &&
      isFALSE(p1$data_vintage_vs_parent$cutoff_changed) && !any(grepl("^vintage", jl_events())),
    "B2 같은 판본 승격 — match · 저널 없음")
put(T1, as.Date("2008-09-30"), modify = function(R) R[Date == as.Date("2006-03-15") & Ticker == "T05", Close := Close + 1])
p2 <- promo(L, T1, "RP_V1_promo2")
v2 <- p2$data_vintage_vs_parent; j2 <- jl_last("vintage_mismatch")
chk(identical(v2$status, "mismatch") && identical(v2$reason, "history_revised") && identical(ul(v2$parts), "raw") &&
      identical(as.integer(unlist(v2$years)), 2006L) && identical(ul(v2$cols), "raw:Close"),
    "B3a 부모 cutoff 이전 과거 행 개정(2006 Close 1행) — mismatch · history_revised · raw · 2006 · raw:Close",
    paste(v2$status, v2$reason, paste(ul(v2$parts), collapse = ","), paste(unlist(v2$years), collapse = ","), paste(ul(v2$cols), collapse = ",")))
chk(!is.null(j2) && identical(j2$base_id, "RP_V1_promo2") && identical(j2$parent, "RP_V1") && identical(j2$src, "ledger") &&
      identical(j2$years, "2006") && identical(j2$cols, "raw:Close"), "B3b jlog 'vintage_mismatch' 1줄(QVEST_RP_JLOG 싱크 · base_id·parent·연도·열)")
put(T1, as.Date("2008-09-30"), modify = function(R) { i <- which(R$Date == as.Date("2007-02-14") & R$Ticker == "T03"); set(R, i, "Vol", flip1(R$Vol[i])) })
p2v <- promo(L, T1, "RP_V1_promo2v"); v2v <- p2v$data_vintage_vs_parent
chk(identical(v2v$status, "mismatch") && identical(v2v$reason, "history_revised") && identical(ul(v2v$cols), "raw:Vol") &&
      identical(as.integer(unlist(v2v$years)), 2007L),
    "B3c ★F1 셀 엔진 유동성 입력 Vol 1행 1바이트 개정 — mismatch · raw:Vol · 2007 (v1 은 match 로 적었다)", paste(ul(v2v$cols), collapse = ","))
put(T1, as.Date("2008-09-30"), modify = function(R) { i <- which(R$Date == as.Date("2005-08-10") & R$Ticker == "T02")
  j <- which(R$Date == as.Date("2005-08-10") & R$Ticker == "T07"); a <- R$Size[i]; set(R, i, "Size", R$Size[j]); set(R, j, "Size", a) })
p2s <- promo(L, T1, "RP_V1_promo2s"); v2s <- p2s$data_vintage_vs_parent
chk(identical(v2s$status, "mismatch") && identical(ul(v2s$cols), "raw:Size"),
    "B3d ★F1 Size 두 종목 값 교환(연 합 보존 · B3 크기 칸 입력) — mismatch · raw:Size", paste(ul(v2s$cols), collapse = ","))
n_before <- sum(jl_events() == "vintage_mismatch")
put(T1, as.Date("2008-09-30"), modify = function(R) R[Date == as.Date("2006-03-15"), High := High + 5])
p2h <- promo(L, T1, "RP_V1_promo2h")
chk(identical(p2h$data_vintage_vs_parent$status, "match") && sum(jl_events() == "vintage_mismatch") == n_before,
    "B3e 음성 대조 — 소비자 코드가 읽지 않는 열(High) 개정은 match · 저널 없음")
put(T1, as.Date("2008-12-31"))                                        # 원상 복구 + 12월까지 연장
p3 <- promo(L, T1, "RP_V1_promo3")
v3 <- p3$data_vintage_vs_parent
chk(identical(p3$data_cutoff, "2008-11-30") && identical(v3$status, "mismatch") && identical(v3$reason, "cutoff_changed") &&
      identical(v3$history, "match") && isTRUE(v3$cutoff_changed),
    "B4a 자식 창 전진(08-31 → 11-30) — mismatch(cutoff_changed) · 과거는 부모 cutoff 재계산으로 match",
    paste(p3$data_cutoff, v3$status, v3$reason, v3$history))
p4 <- promo(L, T1, "RP_V1_promo4", data_cutoff = "2008-08-31")
chk(identical(p4$data_cutoff, "2008-08-31") && identical(p4$data_vintage_vs_parent$status, "match") &&
      identical(p4$data_fingerprint$digest, e1$data_fingerprint$digest),
    "B4b cutoff 지정(부모와 같은 08-31) — 12월까지 늘어난 데이터에서도 부모 지문 그대로 재현(match)")
n_mm <- sum(jl_events() == "vintage_mismatch")
chk(n_mm == 4L, "B4c 저널 vintage_mismatch = 개정 3(Close·Vol·Size) + 창 전진 1 (일치 경로는 무기록)", sprintf("n=%d", n_mm))
## 엔진 열 — engine_path 가 읽는 열(High)이 지문에 들어오고, 자식 열이 부모와 달라도 부모 열로 재측정해 대조한다
ENGD <- file.path(BASE, sprintf("rfdv_%d_eng", Sys.getpid())); dir.create(ENGD, showWarnings = FALSE)
ENGF <- file.path(ENGD, "engine_high.R"); writeLines("FACTORS <- RAWDATA[, .(Date, Ticker, Score = High)]", ENGF)
p5e <- promo(L, T1, "RP_V1_promo5e", engine_path = ENGF, data_cutoff = "2008-08-31")
chk("High" %in% ul(p5e$data_fingerprint$raw$cols) && !("High" %in% ul(e1$data_fingerprint$raw$cols)) &&
      identical(p5e$data_vintage_vs_parent$status, "match") && identical(p5e$data_vintage_vs_parent$history, "match"),
    "B5a engine_path 가 읽는 열(High)은 자식 지문에 들어오고 · 부모(High 없음)와는 부모 열로 재측정해 match(비교 가능성 유지)",
    paste(p5e$data_vintage_vs_parent$status, p5e$data_vintage_vs_parent$history_why %||% ""))
invisible(capture.output(L$rf_open_entry(1L, "RP_ENG_MISSING", "C", engine_path = file.path(ENGD, "nope.R"), root = T1)))
em <- entry_of(L, T1, "RP_ENG_MISSING")
chk(identical(em$data_fingerprint$status, "ok") && any(grepl("^engine_absent:", ul(em$data_fingerprint$why))),
    "B5b 엔진 파일 부재 — 지문은 남기되 why engine_absent(조용한 누락 없음)")
Sys.setenv(QVEST_RF_VINTAGE = "0")
invisible(capture.output(L$rf_open_entry(1L, "RP_OFF", "C", root = T1)))
eo <- entry_of(L, T1, "RP_OFF")
Sys.unsetenv("QVEST_RF_VINTAGE")
chk(identical(eo$data_fingerprint$status, "disabled") && "data_cutoff" %in% names(eo) && is.null(eo$data_cutoff),
    "B6a 끄개 QVEST_RF_VINTAGE=0 — status disabled · data_cutoff null(필드는 있다 = P0-07 이후 개설 표시)")
p6 <- promo(L, T1, "RP_OFF_promo1", parent = "RP_OFF")
chk(identical(p6$data_vintage_vs_parent$status, "unknown") && identical(p6$data_vintage_vs_parent$why, "parent_fingerprint_absent") &&
      identical(jl_last("vintage_unverified")$base_id, "RP_OFF_promo1"),
    "B6b 부모 지문 부재(이전·끈 entry) — unknown + jlog 'vintage_unverified'(일치로 간주 안 함)")
p7 <- promo(L, T1, "RP_ORPHAN_promo1", parent = "NOT_IN_LEDGER")
chk(identical(p7$data_vintage_vs_parent$why, "parent_entry_absent"), "B6c 부모 entry 가 원장에 없음 — unknown(parent_entry_absent)")
T2 <- file.path(BASE, sprintf("rfdv_%d_b", Sys.getpid())); unlink(T2, recursive = TRUE); dir.create(file.path(T2, "06_Registry"), recursive = TRUE)
invisible(capture.output(L$rf_open_entry(1L, "RP_NODATA", "C", root = T2)))
en <- entry_of(L, T2, "RP_NODATA")
chk(identical(en$status, "active") && identical(en$data_fingerprint$status, "absent") && is.null(en$data_cutoff) &&
      identical(ul(en$data_fingerprint$why), c("raw_file_absent", "bm_file_absent")),
    "B6d 데이터 부재 루트 — 개설은 된다 · status absent + 사유(조용한 누락 아님)")

cat("\n=== B-M. 돌연변이 (원장 소스 치환 → 양성 대조 red) ===\n")
mut <- function(from, to) { s <- paste(LSRC, collapse = "\n"); if (lengths(regmatches(s, gregexpr(from, s, fixed = TRUE))) != 1L) return(NULL)
  load_ledger(sub(from, to, s, fixed = TRUE)) }
T3 <- file.path(BASE, sprintf("rfdv_%d_c", Sys.getpid()))
reset <- function() { unlink(T3, recursive = TRUE); put(T3, as.Date("2008-09-30")) }
M1 <- mut('rev <- identical(cmp$status, "mismatch")', "rev <- FALSE")
if (is.null(M1)) ng("BM1 표적 줄 부재(또는 중복) — 검사 갱신 필요") else {
  reset(); invisible(capture.output(M1$rf_open_entry(1L, "RP_V1", "C", root = T3)))
  put(T3, as.Date("2008-09-30"), modify = function(R) R[Date == as.Date("2006-03-15") & Ticker == "T05", Close := Close + 1])
  m1 <- promo(M1, T3, "RP_V1_promo2")
  chk(!identical(m1$data_vintage_vs_parent$status, "mismatch"), "BM1 돌연변이(개정 무시) — B3a 가 잡을 개정을 놓친다(red)")
}
M2 <- mut("fpp <- if (identical(pco, r$data_cutoff) && same_cols) r$fp else", "fpp <- if (TRUE) r$fp else")
if (is.null(M2)) ng("BM2 표적 줄 부재(또는 중복) — 검사 갱신 필요") else {
  reset(); invisible(capture.output(M2$rf_open_entry(1L, "RP_V1", "C", root = T3)))
  put(T3, as.Date("2008-12-31"))
  m2 <- promo(M2, T3, "RP_V1_promo3")
  chk(!identical(m2$data_vintage_vs_parent$history, "match"), "BM2 돌연변이(부모 cutoff 재계산 제거) — B4a 의 history=match 가 깨진다(red)",
      m2$data_vintage_vs_parent$history %||% "")
}
M3p <- mut("raw_cols = p_raw, bm_cols = p_bm)   # 부모 cutoff·부모 열로 다시 잰 지문", "raw_cols = r$L$raw_cols, bm_cols = r$L$bm_cols)")
if (is.null(M3p)) ng("BM3 표적 줄 부재(또는 중복) — 검사 갱신 필요") else {
  reset(); invisible(capture.output(M3p$rf_open_entry(1L, "RP_V1", "C", root = T3)))
  m3 <- promo(M3p, T3, "RP_V1_promo5e", engine_path = ENGF, data_cutoff = "2008-08-31")
  chk(!identical(m3$data_vintage_vs_parent$status, "match"),
      "BM3 돌연변이(부모 열 대신 자식 열로 재측정) — B5a 의 비교 가능성이 깨진다(incomparable → unknown · red)",
      paste(m3$data_vintage_vs_parent$status, m3$data_vintage_vs_parent$why %||% ""))
}
M4e <- mut("has_parent = !is.null(parent), parent_base_id = .pbid, engine_path = engine_path)", "has_parent = !is.null(parent), parent_base_id = .pbid)")
if (is.null(M4e)) ng("BM4 표적 줄 부재(또는 중복) — 검사 갱신 필요") else {
  reset(); invisible(capture.output(M4e$rf_open_entry(1L, "RP_ENG", "C", engine_path = ENGF, root = T3)))
  chk(!("High" %in% ul(entry_of(M4e, T3, "RP_ENG")$data_fingerprint$raw$cols)),
      "BM4 돌연변이(engine_path 미전달) — 엔진이 읽는 열(High)이 지문에서 빠진다(red)")
}
## 계산 중 외부 writer(지문 적재 도중 다른 경로가 원장에 쓴다) — 루트 사본 pin_cache.R(원장이 루트 사본을 먼저 쓴다)에 주입
inj <- c(readLines(PIN, encoding = "UTF-8", warn = FALSE),
         ".pin_fp_orig_load <- pin_fingerprint_load",
         "pin_fingerprint_load <- function(root = NULL, ...) {",
         "  p <- file.path(root, '06_Registry', 'reinforce_ledger_l1.json')",
         "  o <- jsonlite::fromJSON(p, simplifyVector = FALSE)",
         "  if (!any(vapply(o$entries, function(e) identical(e$base_id, 'EXTERNAL_WRITER'), logical(1)))) {",
         "    o$entries[[length(o$entries) + 1L]] <- list(base_id = 'EXTERNAL_WRITER', status = 'active', attempts_used = 0L, attempts = list())",
         "    writeLines(jsonlite::toJSON(o, auto_unbox = TRUE, pretty = TRUE, null = 'null'), p) }",
         "  .pin_fp_orig_load(root, ...) }")
race <- function(Lx) {
  reset(); dir.create(file.path(T3, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
  invisible(capture.output(Lx$rf_open_entry(1L, "RP_SEED", "C", root = T3)))                 # 원장 파일 생성(주입 전)
  writeLines(inj, file.path(T3, "02_Infrastructure/data/pin_cache.R"), useBytes = TRUE)
  invisible(capture.output(Lx$rf_open_entry(1L, "RP_RACE", "C", root = T3)))
  ids <- vapply(Lx$rf_load(1L, T3)$entries, function(e) e$base_id, character(1))
  race_fp <- Filter(function(e) identical(e$base_id, "RP_RACE"), Lx$rf_load(1L, T3)$entries)[[1]]$data_fingerprint$status
  all(c("RP_SEED", "EXTERNAL_WRITER", "RP_RACE") %in% ids) && identical(race_fp, "ok")
}
chk(isTRUE(race(L)), "B7 지문 계산 중 외부 writer 의 entry 보존(계산 뒤 재적재) — 덮어쓰기 0 · 지문 ok")
M5r <- mut("obj <- rf_load(layer, root)   # 재적재", "invisible(NULL)   # 재적재")
if (is.null(M5r)) ng("BM5 표적 줄 부재(또는 중복) — 검사 갱신 필요") else
  chk(!isTRUE(race(M5r)), "BM5 돌연변이(재적재 제거) — 외부 writer entry 가 사라진다(red)")

cat("\n=== B8. 지문 밖 소비 원천(2차 적대검증 F2) — 엔진이 직접 읽는 패널 ===\n")
## 활성 entry 엔진(RP_AUTO_2202_05702)처럼 엔진이 .cache/fundamental_merged.parquet 을 직접 읽으면, 그 패널 개정은 raw/bm/fdb 해시에
##   안 보인다 — 해시가 같다고 '같은 판본(match)'으로 적으면 F1 과 같은 침묵이다.
T5 <- file.path(BASE, sprintf("rfdv_%d_e", Sys.getpid()))
ENGA  <- file.path(ENGD, "engine_aux.R")
writeLines(c('.fm <- arrow::read_parquet(file.path(.CACHE, "fundamental_merged.parquet"))',
             "FACTORS <- RAWDATA[, .(Date, Ticker, Score = Close)]"), ENGA)
ENGAH <- file.path(ENGD, "engine_aux_high.R")
writeLines(c('.fm <- arrow::read_parquet(file.path(.CACHE, "fundamental_merged.parquet"))',
             "FACTORS <- RAWDATA[, .(Date, Ticker, Score = High)]"), ENGAH)
reset5 <- function() { unlink(T5, recursive = TRUE); put(T5, as.Date("2008-09-30"))
  writeBin(as.raw(1:4), file.path(T5, ".cache", "fundamental_merged.parquet")) }   # 이름만 본다(내용 무관)
b8 <- function(Lx) {
  reset5()
  invisible(capture.output(Lx$rf_open_entry(1L, "RP_AUX", "C", engine_path = ENGA, root = T5, data_cutoff = "2008-08-31")))
  invisible(capture.output(Lx$rf_open_entry(1L, "RP_PLAIN", "C", root = T5, data_cutoff = "2008-08-31")))
  list(ea = entry_of(Lx, T5, "RP_AUX"),
       pa = promo(Lx, T5, "RP_AUX_promo1", parent = "RP_AUX", engine_path = ENGA, data_cutoff = "2008-08-31"),
       pc = promo(Lx, T5, "RP_PLAIN_promo1", parent = "RP_PLAIN", engine_path = ENGAH, data_cutoff = "2008-08-31"),
       pn = promo(Lx, T5, "RP_PLAIN_promo2", parent = "RP_PLAIN", data_cutoff = "2008-08-31"))
}
B8 <- b8(L)
chk(identical(B8$ea$data_fingerprint$status, "ok") && identical(ul(B8$ea$data_fingerprint$sources$uncovered), "fundamental_merged.parquet"),
    "B8a 엔진이 직접 읽는 패널은 지문 밖 소비 원천으로 entry 에 기록된다(data_fingerprint.sources.uncovered)",
    paste(ul(B8$ea$data_fingerprint$sources$uncovered), collapse = ","))
va <- B8$pa$data_vintage_vs_parent
ju <- Filter(function(x) identical(x$event, "vintage_unverified") && identical(x$base_id, "RP_AUX_promo1"),
             lapply(readLines(JL, warn = FALSE), fromJSON)); ju <- if (length(ju)) ju[[length(ju)]] else list()
chk(identical(va$status, "unknown") && identical(va$history, "match") && grepl("^history_match_unverified:", va$why %||% "") &&
      "src:fundamental_merged.parquet" %in% ul(va$unverified) && identical(ju$base_id, "RP_AUX_promo1") &&
      grepl("src:fundamental_merged.parquet", ju$why %||% "", fixed = TRUE),
    "B8b ★F2 해시 원천이 같아도 지문 밖 패널을 읽는 엔진의 승격 = unknown(일치로 세지 않음 · history 는 match) + jlog vintage_unverified",
    paste(va$status, va$history, va$why %||% ""))
vc <- B8$pc$data_vintage_vs_parent
chk(identical(vc$status, "unknown") && identical(vc$history, "match") && "src:fundamental_merged.parquet" %in% ul(vc$unverified),
    "B8c 부모 열로 다시 잰 판(자식 엔진이 새 열 High 를 읽음)에도 자식의 지문 밖 원천이 실린다 — unknown",
    paste(vc$status, vc$history, paste(ul(vc$unverified), collapse = ",")))
chk(identical(B8$pn$data_vintage_vs_parent$status, "match") && !length(ul(B8$pn$data_vintage_vs_parent$unverified)),
    "B8d 음성 대조 — 캐시에 패널이 있어도 엔진이 안 읽으면 match(고정 소비자의 캐시 도장 목록은 원천으로 세지 않는다)")
M7u <- mut('else if (identical(cmp$status, "match") && !length(vs$unverified)) "match" else "unknown"',
           'else if (identical(cmp$status, "match")) "match" else "unknown"')
if (is.null(M7u)) ng("BM7 표적 줄 부재(또는 중복) — 검사 갱신 필요") else
  chk(identical(b8(M7u)$pa$data_vintage_vs_parent$status, "match"), "BM7 돌연변이(unverified 무시) — B8b 가 match 로 돌아간다(red)")
M8u <- mut('if (!identical(.rf_s1(fpp$sources$status), "ok")) fpp$sources <- r$fp$sources', "invisible(NULL)")
if (is.null(M8u)) ng("BM8 표적 줄 부재(또는 중복) — 검사 갱신 필요") else
  chk(identical(b8(M8u)$pc$data_vintage_vs_parent$status, "match"), "BM8 돌연변이(재측정본에 원천 범위 미전달) — B8c 가 match 로 돌아간다(red)")

cat("\n=== D. rf_entry_end_dates (원장 재도출) ===\n")
T4 <- file.path(BASE, sprintf("rfdv_%d_d", Sys.getpid())); unlink(T4, recursive = TRUE)
mkart <- function(run, end) { d <- file.path(T4, "stage_artifacts/replication", run); dir.create(d, recursive = TRUE)
  if (!is.na(end)) write_json(list(end_date = end, start_date = "2005-02-01"), file.path(d, "00_manifest.json"), auto_unbox = TRUE)
  file.path("stage_artifacts/replication", run) }
att <- function(run, end) list(n = 1L, artifacts = mkart(run, end), essence = list(port_t = 1))
fx <- list(schema_version = "reinforce_ledger_v2", entries = list(
  list(base_id = "E_SINGLE", attempts = list(att("r1", "2026-09-16"), att("r2", "2026-09-16"), att("r3", "2026-09-16"))),
  list(base_id = "E_MIXED",  attempts = list(att("r4", "2026-09-16"), att("r5", "2026-09-17"), att("r6", "2026-09-17"))),
  list(base_id = "E_WT",     attempts = list(list(n = 1L, artifacts = list(wt_id = "WT-R1", validation = "x.json")))),
  list(base_id = "E_HOLE",   attempts = list(att("r7", "2026-09-18"), att("r8", NA)))))
ed <- L$rf_entry_end_dates(obj = fx, root = T4)
chk(identical(ed$base_id[ed$n_end_dates > 1L], "E_MIXED") && identical(ed$end_dates[ed$base_id == "E_MIXED"], "2026-09-16:1;2026-09-17:2"),
    "D1a 합성 — 혼재 entry 만 지목 · 분포 '날짜:칸수'", paste(ed$base_id[ed$n_end_dates > 1L], collapse = ","))
chk(identical(ed$n_cells, c(3L, 3L, 0L, 2L)) && identical(ed$n_manifest, c(3L, 3L, 0L, 1L)) && identical(ed$idx0, 0:3),
    "D1b WT dict 는 칸 산출물 아님(0) · 산출물 결손은 n_manifest<n_cells 로 드러남 · idx0 = 0-기준")
M6 <- mut("for (a in (e$attempts %||% list())) {", "for (a in head(e$attempts %||% list(), 1L)) {")
if (is.null(M6)) ng("BM6 표적 줄 부재(또는 중복) — 검사 갱신 필요") else
  chk(!any(M6$rf_entry_end_dates(obj = fx, root = T4)$n_end_dates > 1L), "BM6 돌연변이(첫 칸만 읽기) — D1a 의 혼재를 놓친다(red)")
LP <- file.path(CODE, "06_Registry/reinforce_ledger_l1.json")
AUDIT6 <- c(`16` = "RP_20260902_122546_22268", `23` = "RP_20260903_160341_combo",
            `32` = "RP_20260904_163647_18444_rescued_rulefast_promo2", `45` = "RP_20260910_123836_21280_combo_rulefast",
            `47` = "RP_20260912_212323_skipped_base", `57` = "RP_20260917_105807_22632_combo_rulefast")
if (!file.exists(LP)) sk("D2 운영 원장 부재 — 사본 재도출 생략") else {
  cp <- file.path(T4, "ledger_copy.json"); file.copy(LP, cp)                                  # 사본에서만 읽는다
  obj <- fromJSON(cp, simplifyVector = FALSE)
  dd <- L$rf_entry_end_dates(obj = obj, root = CODE)
  a6 <- dd[dd$base_id %in% AUDIT6, ]
  if (nrow(a6) != 6L || any(a6$n_manifest < a6$n_cells)) sk(sprintf("D2 감사 6 entry 산출물 결손(%d/6 · 정리됨?) — 재현 생략", nrow(a6))) else {
    mixed <- dd[dd$n_end_dates > 1L, ]
    idx_ok <- all(vapply(names(AUDIT6), function(k) identical(dd$base_id[dd$idx0 == as.integer(k)], AUDIT6[[k]]), logical(1)))
    chk(all(AUDIT6 %in% mixed$base_id) && idx_ok,
        sprintf("D2 운영 원장 사본 — 감사 end_date 혼재 6 entry(0-기준 16·23·32·45·47·57) 재현 · 현재 혼재 %d개(%s)",
                nrow(mixed), paste(mixed$idx0, collapse = "·")))
    e57 <- dd$end_dates[dd$base_id == AUDIT6[["57"]]]
    chk(grepl("2026-09-16:18", e57) && grepl("2026-09-17:14", e57) && grepl("2026-09-18:4", e57),
        "D3 감사 인용 분포 재현 — entry 57 칸 1~18 = 09-16 · 19~32 = 09-17 · 33~36 = 09-18", e57)
  }
}

for (d in c(T1, T2, T3, T4, T5, ENGD)) unlink(d, recursive = TRUE)
unlink(JL)
for (k in names(.old_env)) if (is.na(.old_env[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(.old_env[[k]]), k))
cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", P, FL, SK))
cat(sprintf('{"test":"rf_data_vintage","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n', P, FL, SK, P + FL + SK))
quit(save = "no", status = if (FL > 0L) 1L else 0L)
