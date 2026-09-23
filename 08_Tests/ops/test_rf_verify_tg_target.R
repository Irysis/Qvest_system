#!/usr/bin/env Rscript
#==============================================================================
# test_rf_verify_tg_target.R — 무인 충실구현 텔레그램 '대상:' 줄 빌더 회귀 검사 (2026-09-13 신설)
#
# 대상 = 02_Infrastructure/ops/rf_replication_verify.R 의 .tg_clip · .tg_target_items · .tg_target_label ·
#   .tg_combo_papers (2026-09-10 신설 — 그날부터 검사 0). 세션 드라이런(tg_dryrun.R)은 줄을 찍기만 하고
#   판정하지 않았고, 운영 요청 슬롯을 읽었고, 줄 앵커 grep 으로 함수를 잘라냈다. 이 검사가 그것을 대체한다.
#
# 막는 실패 3종 (전부 실제로 있었다):
#   A 오귀속 — paper_key 는 키 정렬순, RP_TITLE 은 combo.papers 입력순. 위치로 짝지으면 1403.8125 에
#     2404.08129 의 제목이 붙는다(09-10 드라이런). ★이 검사 신설 중 실측(09-13): 요청 슬롯이 같은 편수의
#     **다른** 결합으로 덮이면 구판(편수만 비교)이 남의 논문 3편을 이 결합 아래에 냈다 → 키 집합 비교로 수리.
#   B 조용한 잘림 — 구판 호출부 substr(TITLE, 1, 52~78) 이 결합 2·3편을 '…' 없이 지웠다.
#   C 줄 길이 — 산출 줄 전부 ≤ telegram_notify.R .TG_CONFIG$BULLET_ITEM_MAX. 상한은 그 config 에서 읽는다.
#     ★신설 중 실측(09-13): 긴 단독 제목 줄 82자(suffix 포함 92자) — cap 이 제목 몫이었다 → 줄 전체로 수리.
#
# 설계:
#   · 검증기 본문(setwd·계약 실행·quit)은 돌리지 않는다. 최상위 **함수 정의 전부**를 샌드박스에 평가한 뒤
#     telegram_notify.R 을 같은 샌드박스에 source 한다 — 운영 순서(정의 → 발송 직전 source 가 %||% 를 덮음) 재현.
#   · 샌드박스 부모 = 패키지 검색경로(이 스크립트 전역을 못 본다). ROOT = 요청 파일이 없는 미끼 디렉터리.
#     짝 원본은 인자로 주입한다 — 픽스처 = 임시 디렉터리의 합성 요청 JSON. 운영 슬롯(가변)을 빌리지 않는다.
#   · 판정은 산출 줄에서 재도출한다(키 토큰 · 제목 머리 · '…' 위치 · nchar). 소스 텍스트·줄 번호를 보지 않는다.
#   · X 절이 판정기마다 위반 주입(위치 짝 · 제목 바꿔치기 · 구판 substr · 상한+1 줄)을 먼저 붉게 만든다 —
#     검출력이 실증되지 않은 판정기는 방어선으로 세지 않는다.
# 돌연변이 실행: QVEST_RPV_R=<고친 검증기 사본> Rscript 08_Tests/ops/test_rf_verify_tg_target.R
#==============================================================================
suppressMessages(library(jsonlite))

.root <- local({
  # 앵커 1순위 = 이 스크립트 위치(worktree 에서 돌린 검사가 main 트리를 검사하지 않게) · 폴백 = env.
  .marker <- file.path("02_Infrastructure", "ops", "rf_replication_verify.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    r <- normalizePath(file.path(dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)), "..", ".."),
                       winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
})
VERIFY_R <- Sys.getenv("QVEST_RPV_R", file.path(.root, "02_Infrastructure/ops/rf_replication_verify.R"))
TG_R     <- file.path(.root, "02_Infrastructure/telegram/telegram_notify.R")
Sys.setenv(QVEST_TG_DRY_RUN = "1")   # 발송 함수는 부르지 않는다 — 혹시의 호출도 드라이런

PASS <- 0L; FAIL <- 0L
ok  <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng  <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- tempfile("rpv_tg_"); dir.create(TMP)
finish <- function() {
  unlink(TMP, recursive = TRUE)
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_verify_tg_target","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(save = "no", status = if (FAIL == 0L) 0L else 1L)
}

cat("=== L. 적재 — 검증기 본문은 돌리지 않는다 ===\n")
ex <- tryCatch(parse(VERIFY_R, keep.source = FALSE, encoding = "UTF-8"), error = function(e) e)
if (inherits(ex, "error")) { ng("L0 검증기 파싱", conditionMessage(ex)); finish() }
SB <- new.env(parent = parent.env(globalenv()))
is_fn_def <- function(e) is.call(e) && is.name(e[[1L]]) && as.character(e[[1L]]) %in% c("<-", "=") &&
  is.name(e[[2L]]) && is.call(e[[3L]]) && identical(e[[3L]][[1L]], as.name("function"))
n_def <- 0L
for (e in ex) if (is_fn_def(e)) { eval(e, SB); n_def <- n_def + 1L }
tg <- tryCatch({ invisible(capture.output(suppressWarnings(suppressMessages(sys.source(TG_R, envir = SB))))); "" },
               error = function(e) conditionMessage(e))
chk(!nzchar(tg), "L1 telegram_notify.R 를 같은 샌드박스에 source (발송 직전과 같은 바인딩)", substr(tg, 1, 160))
DECOY <- file.path(TMP, "decoy_root"); dir.create(DECOY)
assign("ROOT", DECOY, envir = SB)   # 요청 파일 없는 미끼 — 주입을 빠뜨린 기본 경로는 운영 슬롯이 아니라 빈 곳을 읽는다
FN <- c(".tg_clip", ".tg_target_items", ".tg_target_label", ".tg_combo_papers")
miss <- FN[!vapply(FN, function(f) exists(f, envir = SB, inherits = FALSE) && is.function(get(f, envir = SB)), logical(1))]
chk(!length(miss), sprintf("L2 대상 함수 4종 = 검증기 최상위 정의 (함수 정의 %d개 평가)", n_def),
    paste("부재:", paste(miss, collapse = ", ")))
MAX <- tryCatch(get(".TG_CONFIG", envir = SB, inherits = FALSE)$BULLET_ITEM_MAX, error = function(e) NULL)
MAX_OK <- is.numeric(MAX) && length(MAX) == 1L && is.finite(MAX) && MAX > 0
chk(MAX_OK, sprintf("L3 줄 상한 = telegram_notify.R .TG_CONFIG$BULLET_ITEM_MAX = %s", if (MAX_OK) MAX else "부재"))
if (nzchar(tg) || length(miss) || !MAX_OK) finish()
MAX <- as.integer(MAX)
clip  <- get(".tg_clip", SB);         items     <- get(".tg_target_items", SB)
label <- get(".tg_target_label", SB); papers_of <- get(".tg_combo_papers", SB)
safe  <- function(expr) tryCatch(expr, error = function(e) sprintf("<error: %s>", conditionMessage(e)))

# ── 판정기 (산출 줄에서 재도출) ─────────────────────────────────────────────────
ELL <- "\u2026"; DOT <- "\u00b7"; DASH <- "\u2014"
HEAD_N   <- 16L   # 제목 머리 — 가장 좁은 제목 몫(키 21자 줄)에서도 잘리지 않는 길이
key_rx   <- function(k) paste0("(?<![0-9A-Za-z._/-])\\Q", k, "\\E(?![0-9A-Za-z._/-])")
has_key  <- function(lines, k) grepl(key_rx(k), lines, perl = TRUE)
head_of  <- function(t) substr(t, 1L, HEAD_N)
has_head <- function(lines, t) nzchar(t) & grepl(head_of(t), lines, fixed = TRUE)
# A: 제목 머리가 실린 줄은 그 제목의 짝 키 **하나만** 실어야 한다
misattributed <- function(lines, truth) Filter(function(ln) {
  ks <- truth$key[vapply(truth$key,   function(k) has_key(ln, k),  logical(1))]
  ts <- truth$key[vapply(truth$title, function(t) has_head(ln, t), logical(1))]
  length(ts) > 0L && !(length(ts) == 1L && identical(ks, ts))
}, lines)
key_counts <- function(lines, keys) vapply(keys, function(k) sum(has_key(lines, k)), integer(1))
any_title  <- function(lines, titles) any(vapply(titles, function(t) any(has_head(lines, t)), logical(1)))
leaked     <- function(lines, foreign) Filter(function(ln)
  any(vapply(foreign$key, function(k) has_key(ln, k), logical(1))) || any_title(ln, foreign$title), lines)
titled     <- function(lines, truth) vapply(which(nzchar(truth$title)), function(i) {
  l <- lines[has_key(lines, truth$key[i])]
  length(l) == 1L && has_head(l, truth$title[i]) }, logical(1))
# B: 줄 안의 제목이 온전(full) / '…' 로 드러낸 잘림 / 표시 없는 잘림(silent) / 부재 중 무엇인가
render_state <- function(line, title, suffix = "") {
  if (length(line) != 1L) return(sprintf("lines_%d", length(line)))
  s <- regexpr(head_of(title), line, fixed = TRUE)
  if (s < 0L) return("absent")
  rest <- substring(line, s)
  if (nzchar(suffix)) {
    if (!endsWith(rest, suffix)) return("suffix_lost")
    rest <- substr(rest, 1L, nchar(rest) - nchar(suffix))
  }
  if (identical(rest, title)) return("full")
  if (endsWith(rest, ELL)) {
    body <- substr(rest, 1L, nchar(rest) - 1L)
    if (nzchar(body) && startsWith(title, body)) return("clipped_visible")
  }
  if (startsWith(title, rest)) "silent" else "mangled"
}
# C: 문자 수(발신기 가드와 같은 nchar chars) · 줄 안 개행
over_limit <- function(lines) lines[nchar(lines, type = "chars") > MAX | grepl("[\r\n]", lines)]
show <- function(x, n = 4L) paste(head(sprintf("[%d] %s", nchar(x), x), n), collapse = " | ")

# ── 위반 주입용 구판 (판정기 검출력 실증 전용) ─────────────────────────────────
TGT <- "대상: "
mut_positional <- function(title, pkey) {   # 09-10 드라이런이 잡은 결함 — 정렬 키 × 입력순 제목을 위치로 짝
  keys <- strsplit(sub("^combo:", "", pkey), "+", fixed = TRUE)[[1]]
  tt   <- strsplit(sub("^결합: ", "", title), " + ", fixed = TRUE)[[1]]
  c(paste0(TGT, "결합"), sprintf("  %s %s %s %s", DOT, keys, DASH, tt))
}
mut_substr <- function(title, n) paste0(TGT, substr(title, 1L, n))   # 구판 호출부 — 말없는 절단

# ── 픽스처 (인라인 — 운영 레지스트리를 읽지 않는다) ─────────────────────────────
P3 <- data.frame(stringsAsFactors = FALSE,        # 실사고 결합 · combo.papers **입력순**
  key   = c("2404.08129", "1403.8125", "2301.09173"),
  title = c("One Factor to Bind the Cross-Section of Returns",
            "Maximum drawdown, recovery, and momentum",
            "Pinchuk (2023) Labor Income Risk and the Cross-Section of Expected Returns"))
PKEY3  <- paste0("combo:", paste(sort(P3$key), collapse = "+"))   # 런처 규칙: 키 정렬
TITLE3 <- paste0("결합: ", paste(P3$title, collapse = " + "))      # 런처 규칙: 입력순 연접
FOREIGN <- data.frame(stringsAsFactors = FALSE,   # 슬롯을 덮은 다음 요청 — 같은 3편짜리 다른 결합
  key   = c("2513.00003", "2513.00001", "2513.00002"),
  title = c("Zeta: a foreign paper from the next request",
            "Alpha: another foreign paper in that slot",
            "Beta: third foreign paper, same slot"))
P5 <- data.frame(stringsAsFactors = FALSE,        # 원장 실재 최대 편수(5) · 긴 키 모양(저자_연도 21자 · 구식 arXiv)
  key   = c("jegadeesh_titman_1993", "cond-mat/9913001", "2513.00042", "2513.1234", "2513.99999"),
  title = c("Returns to Buying Winners and Selling Losers: Implications for Stock Market Efficiency",
            "Synthetic fixture: price-fluctuation scaling in an order book that does not exist",
            "코스피200·코스닥150 낙폭 회복 경로와 모멘텀 비대칭의 강건성 재검토 — 검사용 합성 제목",
            "Short synthetic title",
            ""))                                    # 제목 없는 재료 = 키만
PKEY5  <- paste0("combo:", paste(sort(P5$key), collapse = "+"))
TITLE5 <- paste0("결합: ", paste(P5$title, collapse = " + "))
T_LONG  <- "An Extremely Long Paper Title About Drawdown Geometry, Path Dependence, and the Cross-Section of Expected Stock Returns in Emerging Markets"
T_KO    <- "코스피200·코스닥150 유니버스에서 낙폭 기하 모멘텀과 단일 결속 팩터의 직교성 — 경로형태 신호의 횡단면 가격결정력 재검토 및 부분표본 강건성 분석 (검사용 합성 제목)"
T_SHORT <- "Betting Against Beta"
SUF  <- " (측정 등급 F)"
KEY1 <- "2513.00077"
rows <- function(df) lapply(seq_len(nrow(df)), function(i)
  list(key = df$key[i], title = df$title[i], url = paste0("https://arxiv.org/abs/", df$key[i])))
write_req <- function(name, obj = NULL, raw = NULL) {
  p <- file.path(TMP, name)
  if (!is.null(raw)) writeLines(raw, p) else write(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  p
}

cat("\n=== X. 판정기 검출력 — 위반 주입이 먼저 붉어져야 판정기를 믿는다 ===\n")
good <- sprintf("  %s %s %s %s", DOT, P3$key, DASH, P3$title)
chk(!length(misattributed(good, P3)), "X1 올바른 짝 줄은 오귀속으로 잡히지 않는다 (음성 대조)", show(misattributed(good, P3)))
chk(all(sort(P3$key) != P3$key), "X2 픽스처 전제: 입력순이 정렬순과 모든 위치에서 다르다 (위치로 짝지으면 전 편 오귀속)")
mp <- mut_positional(TITLE3, PKEY3)
chk(length(misattributed(mp, P3)) == nrow(P3),
    sprintf("X3 위치 짝 주입 → 오귀속 %d/%d 줄 검출 (09-10 결함)", length(misattributed(mp, P3)), nrow(P3)), show(mp))
sw <- good; sw[1] <- sub(head_of(P3$title[1]), head_of(P3$title[2]), sw[1], fixed = TRUE)
chk(length(misattributed(sw, P3)) >= 1L, "X4 한 줄의 제목만 남의 것으로 바꿔치기 주입 → 검출", show(sw))
chk(identical(render_state(mut_substr(T_LONG, 78L), T_LONG), "silent") &&
    identical(render_state(paste0(TGT, substr(T_LONG, 1L, 70L), ELL), T_LONG), "clipped_visible") &&
    identical(render_state(paste0(TGT, T_SHORT), T_SHORT), "full"),
    "X5 잘림 판정기: 구판 substr(…, 78) = silent · '…' = clipped_visible · 온전 = full")
for (n in c(52L, 78L)) {
  old  <- mut_substr(TITLE3, n)
  lost <- P3$key[!vapply(seq_len(nrow(P3)), function(i) has_key(old, P3$key[i]) || has_head(old, P3$title[i]), logical(1))]
  chk(length(lost) >= 1L, sprintf("X6 구판 결합 제목 substr(…, %d) 주입 → 사라진 재료 %d편 검출 (%s)", n, length(lost),
                                  paste(lost, collapse = ", ")), show(old))
}
chk(!length(over_limit(strrep("가", MAX))) && length(over_limit(strrep("가", MAX + 1L))) == 1L &&
    length(over_limit("a\nb")) == 1L, sprintf("X7 줄 판정기: %d자 통과 · %d자 검출 · 줄 안 개행 검출", MAX, MAX + 1L))

cat("\n=== H. 격리 — 짝 원본을 주입하지 않으면 운영 슬롯이 아니라 빈 미끼 루트를 읽는다 ===\n")
h <- safe(items(TITLE3, PKEY3))
chk(all(key_counts(h, P3$key) == 1L) && !any_title(h, P3$title),
    "H1 주입 없는 기본 경로 = 짝 없음 → 키만 (샌드박스가 운영 요청 파일에 닿지 않는다)", show(h))
REQ3 <- write_req("req_combo3.json", list(status = "in_progress",
  paper = list(title = TITLE3, paper_title = TITLE3, paper_key = PKEY3, source = "combination"),
  combo = list(papers = rows(P3), count_paper = FALSE)))
# 운영 호출 형태는 인자 없는 .tg_target_items(TITLE, PKEY) 다. 아래 절은 전부 짝 원본을 주입하므로,
#   기본값이 짝 원본을 안 거치게 바뀌면(예: papers = NULL) 운영만 조용히 키만 내고 검사는 초록일 수 있다.
#   ⇒ 짝 원본 읽기를 합성 요청을 읽는 대역으로 잠시 바꿔 **기본값 경로**가 제목을 내는지 본다.
.real_reader <- get(".tg_combo_papers", envir = SB)
assign(".tg_combo_papers", function(...) .real_reader(REQ3), envir = SB)
h2 <- safe(items(TITLE3, PKEY3))
assign(".tg_combo_papers", .real_reader, envir = SB)
chk(all(titled(h2, P3)) && !length(misattributed(h2, P3)),
    "H2 운영 호출 형태(인자 없음)도 짝 원본을 거쳐 제 짝 제목을 낸다", show(h2))

cat("\n=== A. 오귀속 ===\n")
A1 <- safe(items(TITLE3, PKEY3, papers = papers_of(REQ3)))
cat(paste0("        ", A1), sep = "\n")
chk(!length(misattributed(A1, P3)), "A1 제목은 제 키의 줄에만 실린다 (정렬순 키 × 입력순 쌍)", show(misattributed(A1, P3)))
chk(all(key_counts(A1, P3$key) == 1L), "A2 재료 3편의 키가 한 줄씩", paste(key_counts(A1, P3$key), collapse = "/"))
chk(all(titled(A1, P3)), "A3 짝 원본이 있으면 제목을 버리지 않는다", show(A1))
broken <- list(
  list(why = "가변 슬롯 — 같은 3편짜리 다른 결합으로 덮였다 (09-13 실측)",
       path = write_req("req_stale.json", list(status = "pending",
                paper = list(paper_key = paste0("combo:", paste(sort(FOREIGN$key), collapse = "+"))),
                combo = list(papers = rows(FOREIGN))))),
  list(why = "부분 겹침 — 2편은 같고 1편은 남의 논문",
       path = write_req("req_overlap.json", list(combo = list(papers = rows(rbind(P3[1:2, ], FOREIGN[1, ])))))),
  list(why = "중복 키 — 편수만 같다",
       path = write_req("req_dup.json", list(combo = list(papers = rows(P3[c(1, 1, 2), ]))))),
  list(why = "combo 블록 없음 — 단독 요청이 슬롯에 있다",
       path = write_req("req_single.json", list(paper = list(paper_key = KEY1, paper_title = T_SHORT)))),
  list(why = "요청 파일 부재", path = file.path(TMP, "absent_request.json")),
  list(why = "깨진 JSON", path = write_req("req_broken.json", raw = '{"combo": {"papers": [{"key": "2404.08129", "title": ')))
POOL <- c(h, h2, A1)
for (b in broken) {
  L <- safe(items(TITLE3, PKEY3, papers = papers_of(b$path)))
  POOL <- c(POOL, L)
  bad <- c(leaked(L, FOREIGN), misattributed(L, P3))
  kc  <- key_counts(L, P3$key)
  chk(!length(bad) && all(kc == 1L) && !any_title(L, P3$title),
      sprintf("A4 %s → 이 결합의 키만 · 남의 짝 0 · 지어낸 제목 0", b$why),
      sprintf("누출·오귀속 %d · 키 %s · %s", length(bad), paste(kc, collapse = "/"), show(L)))
}
A5 <- safe(items(T_SHORT, KEY1, papers = papers_of(broken[[1]]$path)))
POOL <- c(POOL, A5)
chk(length(A5) == 1L && identical(render_state(A5, T_SHORT), "full") && !length(leaked(A5, FOREIGN)),
    "A5 단독 요청은 한 줄 · 슬롯에 남은 결합 짝에 오염되지 않는다", show(A5))

cat("\n=== B. 조용한 잘림 ===\n")
chk(nchar(T_LONG) > MAX && nchar(T_KO) > MAX && any(nchar(P5$key) + nchar(P5$title) > MAX),
    sprintf("B0 픽스처 전제: 긴 제목 %d·%d자 · 5편 재료 줄이 줄 상한 %d 를 넘는다 (잘림이 실제로 일어난다)",
            nchar(T_LONG), nchar(T_KO), MAX))
b1 <- safe(items(T_LONG, KEY1)); b2 <- safe(items(T_LONG, KEY1, suffix = SUF)); b3 <- safe(items(T_KO, KEY1))
POOL <- c(POOL, b1, b2, b3)
chk(identical(render_state(b1, T_LONG), "clipped_visible"), "B1 긴 단독 제목 → '…' 로 잘림을 드러낸다", render_state(b1, T_LONG))
chk(identical(render_state(b2, T_LONG, SUF), "clipped_visible"), "B2 suffix 가 있어도 '…' 는 제목 끝 · suffix 는 온전",
    render_state(b2, T_LONG, SUF))
chk(identical(render_state(b3, T_KO), "clipped_visible"), "B3 긴 한글(다바이트) 제목 → '…'", render_state(b3, T_KO))
b4 <- c(safe(items(T_SHORT, KEY1)), safe(items(T_SHORT, KEY1, suffix = SUF)))
POOL <- c(POOL, b4)
chk(nchar(T_SHORT) + nchar(SUF) <= MAX %/% 2L &&
    identical(c(render_state(b4[1], T_SHORT), render_state(b4[2], T_SHORT, SUF)), c("full", "full")) &&
    !any(grepl(ELL, b4, fixed = TRUE)), "B4 짧은 제목은 온전하고 '…' 가 붙지 않는다 (오탐 없음)", show(b4))
x_eq <- strrep("a", MAX); x_over <- strrep("가", MAX + 1L); co <- safe(clip(x_over, MAX))
chk(identical(safe(clip(x_eq, MAX)), x_eq) && nchar(co) == MAX && endsWith(co, ELL) &&
    startsWith(x_over, substr(co, 1L, nchar(co) - 1L)),
    sprintf("B5 .tg_clip: %d자 = 무변 · %d자(한글) → %d자 + '…'", MAX, MAX + 1L, MAX), show(co))
cn <- safe(clip("Line one\r\nline two\nthree", MAX))
chk(!grepl("[\r\n]", cn) && grepl("Line one", cn, fixed = TRUE) && grepl("three", cn, fixed = TRUE),
    "B6 제목 안 개행은 한 줄로 편다 (불릿이 둘로 안 쪼개진다)", cn)
REQ5 <- write_req("req_combo5.json", list(paper = list(paper_key = PKEY5), combo = list(papers = rows(P5))))
SUF5 <- " (측정 등급 C)"
B7 <- safe(items(TITLE5, PKEY5, suffix = SUF5, papers = papers_of(REQ5)))
POOL <- c(POOL, B7)
cat(paste0("        ", B7), sep = "\n")
st <- vapply(which(nzchar(P5$title)), function(i) {
  l <- B7[has_key(B7, P5$key[i])]
  if (length(l) != 1L) "key_line_missing" else render_state(l, P5$title[i]) }, character(1))
chk(all(st %in% c("full", "clipped_visible")), "B7 5편 결합 재료 줄: 온전 또는 '…' — 표시 없는 잘림 0", paste(st, collapse = ","))
chk(!length(misattributed(B7, P5)) && all(key_counts(B7, P5$key) == 1L) && all(titled(B7, P5)),
    "B8 5편 결합: 키 5개 한 줄씩 · 제목은 제 키에 (제목 없는 재료는 키만)", show(B7, 6L))
chk(sum(grepl(SUF5, B7, fixed = TRUE)) == 1L && endsWith(B7[1], SUF5), "B9 suffix 는 첫 줄 꼬리에 한 번", show(B7, 1L))
lab3 <- safe(label(TITLE3, PKEY3)); lab5 <- safe(label(TITLE5, PKEY5))
labs <- c(safe(label(T_LONG, KEY1)), safe(label(T_SHORT, KEY1)))
POOL <- c(POOL, lab3, lab5, labs)
chk(all(key_counts(lab3, P3$key) == 1L) && !any(grepl(ELL, lab3, fixed = TRUE)),
    "B10 3편 결합 캡션 = 키 3개 전부 (구판은 제목 연접 절단에 2·3편이 사라졌다)", show(lab3))
kp <- key_counts(lab5, P5$key) == 1L
chk(length(lab5) == 1L && (all(kp) || (endsWith(lab5, ELL) && any(kp))),
    sprintf("B11 5편 결합 캡션: 키 %d/%d · 못 담은 키는 '…' 로 드러난다", sum(kp), length(kp)), show(lab5))
chk(identical(render_state(labs[1], T_LONG), "clipped_visible") && identical(render_state(labs[2], T_SHORT), "full"),
    "B12 단독 캡션: 긴 제목 '…' · 짧은 제목 온전", show(labs))

cat("\n=== C. 줄 길이 ===\n")
POOL <- c(POOL, safe(items(T_LONG, "jegadeesh_titman_1993", suffix = " · 강화 25회 소진 (측정 등급 C)")),
          safe(items(T_KO, KEY1, suffix = SUF)))
bad <- over_limit(POOL)
chk(!length(bad), sprintf("C1 산출 줄 %d개 전부 ≤ %d자 · 줄 안 개행 0 (최장 %d자)", length(POOL), MAX, max(nchar(POOL))),
    show(bad))
chk(any(grepl(ELL, POOL, fixed = TRUE)), "C2 전제: 풀에 실제로 잘린 줄이 있다 — 상한 검사가 공회전하지 않는다")
finish()
