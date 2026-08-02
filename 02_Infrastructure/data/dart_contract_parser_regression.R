#!/usr/bin/env Rscript
#==============================================================================
# dart_contract_parser_regression.R — 파서 v3 회귀 검증 (FQ-002 / FQ-125 선행)
#
# 2026-08-03 신설. v3 는 구서식(EUC-KR 바이트) 커버를 위해 **바이트→텍스트 디코딩**을
#   교체했다. 신형(UTF-8) 경로가 그대로인지는 주장이 아니라 실측으로 증명해야 한다.
#
# 방법: 체크포인트 CSV 에 저장된 값이 곧 **v2 의 산출물**이다(2026-08-02 실크롤).
#   같은 rcept_no 의 원문을 다시 받아 v3 로 파싱하고 저장값과 전 필드 대조한다.
#   → "v3 로 재파싱해도 값이 안 변한다"의 직접 증거. 별도 v2 재구현이 필요 없다
#     (재구현 대조는 전사 오류가 끼어들 여지를 만든다).
#
# ★원문 캐시: 응답 바이트를 .cache/dart/contract_docs/<rcept_no>.bin 에 보존한다.
#   1회 지불 후 재실행은 **API 호출 0**. 앞으로의 재파싱·서식 조사도 무료가 된다.
#
# ★해석 주의: 저장값과 다르면 두 가능성이다 — (a) v3 회귀 (b) DART 원문 재발행.
#   그래서 불일치는 요약이 아니라 **행 단위로 CSV 에 남긴다**(집계로 뭉개면 진단 불가).
#
# Usage:
#   [REG_START=202308 REG_END=202607 DART_DAILY_BUDGET=7000 REG_CACHE_ONLY=1] \
#     Rscript 02_Infrastructure/data/dart_contract_parser_regression.R
#   REG_CACHE_ONLY=1 → 캐시에 있는 문서만 검증(네트워크 미사용).
# 산출: .cache/dart/contract_regression_<START>_<END>.csv (불일치 행) + stdout 요약
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

# 금칙 ④: CLAUDE_PROJECT_DIR 먼저 + marker 로 정체성 검증(금칙 ③ — 존재 검사 금지)
.rg_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  cands <- gsub("\\\\", "/", cands)                 # 정규화를 검사보다 **먼저**
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
ROOT <- .rg_root()
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")

CKDIR    <- file.path(ROOT, ".cache/dart/contract_backfill")
DOCDIR   <- file.path(ROOT, ".cache/dart/contract_docs")
dir.create(DOCDIR, recursive = TRUE, showWarnings = FALSE)
CACHE_ONLY <- nzchar(Sys.getenv("REG_CACHE_ONLY", ""))
BUDGET     <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "7000"))
START      <- Sys.getenv("REG_START", "202308")
END        <- Sys.getenv("REG_END",   "202607")

KEY <- ""
if (!CACHE_ONLY) {
  env <- readLines(file.path(ROOT, ".env"), warn = FALSE)
  KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
  if (!nzchar(KEY)) stop("DART_API_KEY 미발견 (.env)")
}

fs <- list.files(CKDIR, pattern = "^[0-9]{6}[.]csv$", full.names = TRUE)
fs <- fs[basename(fs) >= paste0(START, ".csv") & basename(fs) <= paste0(END, ".csv")]
if (!length(fs)) stop(sprintf("대상 체크포인트 0개 (%s..%s)", START, END))

D <- rbindlist(lapply(fs, function(f)
        fread(f, colClasses = list(character = c("corp_code", "rcept_no")))), fill = TRUE)
D <- D[!is.na(rcept_no) & nzchar(rcept_no)]
cat(sprintf("[reg] 대상 %s..%s | %d개월 | %d행 | cache_only=%s\n",
            START, END, length(fs), nrow(D), CACHE_ONLY))
cat("[reg] 저장(v2) parse_status 분포:\n"); print(D[, .N, by = parse_status][order(-N)])

# ── 정본 회귀 기준 = **핀된 v2 를 같은 바이트에 돌린 결과** ────────────────────
# 체크포인트 저장값은 단일 파서의 산출이 아니다(실측): OK 행은 크롤 시점 파서,
# 실패 행은 이후 dart_contract_reparse_failures.R 이 v2 로 덮어썼다. 그래서 저장값
# 대조만으로는 "내 변경이 바꿨나"와 "세대가 달라 원래 다르다"를 가를 수 없다.
# → v2(핀 SHA)를 **같은 캐시 바이트**에 돌려 v3 와 1:1 비교한다. 이게 회귀 판정이고,
#   저장값 대조는 진단(세대 차이 노출)으로 병기한다.
V2_PIN <- Sys.getenv("REG_V2_PIN", "6a51d413")   # v3 직전 판
.load_v2 <- function() {
  # 금칙 ⑤: 셸 리다이렉션·연쇄 금지 — system2 인자 + stdout= 로만.
  out <- suppressWarnings(system2("git", c("-C", ROOT, "show",
           paste0(V2_PIN, ":02_Infrastructure/data/dart_contract_doc_parser.R")),
           stdout = TRUE, stderr = FALSE))
  st <- attr(out, "status"); st <- if (is.null(st)) 0L else as.integer(st)
  if (st != 0L || !length(out)) return(NULL)     # 결손을 값으로 내려앉히지 않는다
  f <- tempfile(fileext = ".R"); writeLines(out, f, useBytes = TRUE)
  e <- new.env()
  okl <- tryCatch({ sys.source(f, envir = e); TRUE }, error = function(x) FALSE)
  unlink(f, force = TRUE)
  if (!okl || !is.function(e$parse_contract_doc)) return(NULL)
  # v2 는 fetch 를 내장한다. httr 함수를 이 환경에서 가려 **캐시 바이트를 먹인다**
  # (재구현이 아니라 v2 자신의 코드를 그대로 관통시켜야 전사 오류가 안 낀다).
  e$.FEED <- NULL; e$.SINK <- NULL
  e$write_disk  <- function(path, overwrite = TRUE) { e$.SINK <- path; NULL }
  e$timeout     <- function(x) NULL
  e$status_code <- function(r) 200L
  e$GET <- function(url, query, ...) {           # force(...) 없으면 write_disk 가 지연평가로 미발화
    invisible(list(...)); writeBin(e$.FEED, e$.SINK); structure(list(), class = "stubresp")
  }
  e
}
V2 <- .load_v2()
v2_parse <- function(rawb) { V2$.FEED <- rawb; V2$parse_contract_doc("STUB", "NOKEY") }

num_eq <- function(a, b, tol = 1e-9) {
  if (is.na(a) && is.na(b)) return(TRUE)
  if (is.na(a) || is.na(b)) return(FALSE)
  if (a == b) return(TRUE)
  d <- abs(a - b); s <- max(abs(a), abs(b), 1)
  d / s <= tol
}
lgl_eq <- function(a, b) (is.na(a) && is.na(b)) || (!is.na(a) && !is.na(b) && a == b)

calls <- 0L; halted <- FALSE
n_done <- 0L; n_uncached <- 0L
diffs <- list(); v2diffs <- list()
encs <- character(0); chks <- character(0); news <- character(0)
audit <- list()   # ratio_check × is_correction 교차표 + 의심 행 원장
# ★최상위 if/else 는 한 줄로 붙이거나 { } 로 감쌀 것 — 쪼개면 "unexpected 'else'" 로
#   스크립트가 죽는다(daily_refresh r18 블록 실사고와 동형). 여기서 실제로 한 번 밟았다.
if (is.null(V2)) {
  cat(sprintf("[reg] ⚠ v2 핀(%s) 로드 실패 — 정본 회귀축 미측정\n", V2_PIN))
} else {
  cat(sprintf("[reg] v2 핀 로드 OK (%s) — 정본 회귀축 = v2 vs v3 (동일 바이트)\n", V2_PIN))
  # ★기능 프로브: 참조가 **살아서 파싱하는지** 확인한다. 스텁이 죽어 값을 전부 NA 로
  #   내면 v3 도 NA 인 행에서 '일치'가 나서 축 전체가 공허해진다("빈 결과 = 합격" 계통).
  #   두 방향 다 건다 — 정상 문서에서 값을 뽑아야 하고, 오류 바디는 UNZIP_FAIL 이어야 한다.
  probe_f <- head(list.files(file.path(ROOT, ".cache/dart/contract_docs"),
                             pattern = "[.]bin$", full.names = TRUE), 1)
  live <- FALSE
  if (length(probe_f)) {
    pp <- tryCatch(v2_parse(readBin(probe_f, "raw", n = file.info(probe_f)$size)),
                   error = function(e) NULL)
    live <- !is.null(pp) && identical(pp$parse_status, "OK") &&
            isTRUE(!is.na(pp$contract_amount) && pp$contract_amount > 0)
  }
  errb <- charToRaw('<result><status>014</status><message>x</message></result>')
  pe <- tryCatch(v2_parse(errb), error = function(e) NULL)
  live_err <- !is.null(pe) && identical(pe$parse_status, "UNZIP_FAIL")
  if (!live || !live_err) {
    cat(sprintf("[reg] ❌ v2 참조 기능 프로브 실패 (parse_live=%s err_live=%s) — 축이 공허하다\n",
                live, live_err))
    quit(status = 4)
  }
  cat("[reg] v2 참조 기능 프로브 PASS (정상문서 파싱 ∧ 오류바디 UNZIP_FAIL)\n")
}

for (i in seq_len(nrow(D))) {
  rc <- as.character(D$rcept_no[i])
  cf <- file.path(DOCDIR, paste0(rc, ".bin"))
  if (!file.exists(cf)) {
    if (CACHE_ONLY) { n_uncached <- n_uncached + 1L; next }
    if (calls >= BUDGET) { cat(sprintf("[reg] 예산 도달 (%d) — 재실행 시 캐시분은 무료\n", calls)); halted <- TRUE; break }
    calls <- calls + 1L
    Sys.sleep(0.35)
  }
  pr <- tryCatch(parse_contract_doc(rc, KEY, is_correction = D$is_correction[i], cache_dir = DOCDIR),
                 error = function(e) NULL)
  if (is.null(pr)) {
    diffs[[length(diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i], field = "EXCEPTION",
                                              stored = NA_character_, v3 = NA_character_)
    next
  }
  # ★한도 소진을 '원문 없음'으로 기록하지 않는다 — 즉시 halt (구 파서의 급소였다)
  if (identical(pr$parse_status, "RATE_LIMIT_020")) {
    cat(sprintf("[reg] DART status 020 (일한도) at %s — halt (calls=%d)\n", rc, calls))
    halted <- TRUE; break
  }
  n_done <- n_done + 1L
  e1 <- pr$doc_encoding; encs <- c(encs, if (is.null(e1) || is.na(e1)) "NA" else e1)
  chks <- c(chks, pr$ratio_check)
  news <- c(news, pr$parse_status)
  audit[[length(audit) + 1L]] <- data.table(
    rcept_no = rc, ym = D$ym[i], corp_name = D$corp_name[i],
    is_correction = isTRUE(D$is_correction[i]), parse_status = pr$parse_status,
    ratio_check = pr$ratio_check, contract_amount = pr$contract_amount,
    recent_revenue = pr$recent_revenue, disclosed_ratio_pct = pr$disclosed_ratio_pct)

  # ── 정본 축: v2(핀) vs v3, 같은 바이트 ──────────────────────────────────────
  if (!is.null(V2)) {
    rb2 <- readBin(cf, "raw", n = file.info(cf)$size)
    p2 <- tryCatch(v2_parse(rb2), error = function(e) NULL)
    if (is.null(p2)) {
      v2diffs[[length(v2diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i],
        field = "V2_EXCEPTION", v2 = NA_character_, v3 = NA_character_)
    } else {
      # v2 는 원문부재/한도를 전부 UNZIP_FAIL 로 뭉갰다 — 그 재라벨은 **의도된 변경**이라
      # 회귀가 아니다. 값 필드는 예외 없이 일치해야 한다.
      RELABEL <- c("NO_SOURCE_CORRECTION", "NO_SOURCE_014", "RATE_LIMIT_020", "DECODE_FAIL")
      c2 <- list(contract_amount  = num_eq(p2$contract_amount,  pr$contract_amount),
                 recent_revenue   = num_eq(p2$recent_revenue,   pr$recent_revenue),
                 ratio_to_revenue = num_eq(p2$ratio_to_revenue, pr$ratio_to_revenue),
                 is_amendment     = lgl_eq(p2$is_amendment,     pr$is_amendment),
                 rounding_flag    = lgl_eq(p2$rounding_flag,    pr$rounding_flag),
                 fx_flag          = lgl_eq(p2$fx_flag,          pr$fx_flag),
                 parse_status     = identical(p2$parse_status, pr$parse_status) ||
                                    (identical(p2$parse_status, "UNZIP_FAIL") &&
                                     pr$parse_status %in% RELABEL))
      for (f in names(c2)) if (!isTRUE(c2[[f]]))
        v2diffs[[length(v2diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i], field = f,
          v2 = as.character(p2[[f]]), v3 = as.character(pr[[f]]))
    }
  }

  cmp <- list(
    contract_amount  = num_eq(D$contract_amount[i],  pr$contract_amount),
    recent_revenue   = num_eq(D$recent_revenue[i],   pr$recent_revenue),
    ratio_to_revenue = num_eq(D$ratio_to_revenue[i], pr$ratio_to_revenue),
    parse_status     = identical(as.character(D$parse_status[i]), pr$parse_status),
    is_amendment     = lgl_eq(as.logical(D$is_amendment[i]), pr$is_amendment),
    rounding_flag    = lgl_eq(as.logical(D$rounding_flag[i]), pr$rounding_flag),
    fx_flag          = lgl_eq(as.logical(D$fx_flag[i]),       pr$fx_flag))
  for (f in names(cmp)) if (!isTRUE(cmp[[f]]))
    diffs[[length(diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i], field = f,
      stored = as.character(D[[f]][i]), v3 = as.character(pr[[f]]))
  if (n_done %% 250L == 0L)
    cat(sprintf("[reg] %d/%d 검증 (calls=%d, 불일치 %d)\n", n_done, nrow(D), calls, length(diffs)))
}

cat(sprintf("\n[reg] 검증 %d행 / API 호출 %d / 미캐시 스킵 %d / halted=%s\n",
            n_done, calls, n_uncached, halted))
if (length(encs)) { cat("[reg] doc_encoding 분포: "); print(table(encs, useNA = "ifany")) }
if (length(chks)) { cat("[reg] ratio_check 분포: "); print(table(chks, useNA = "ifany")) }
if (length(news)) { cat("[reg] v3 parse_status 분포: "); print(table(news, useNA = "ifany")) }

# ★ratio_check(공시 동봉 매출액대비% 대조)는 회귀 판정이 아니라 **무결성 진단**이다.
#   정정공시는 상단에 "정정 전/후" 비교표가 실려 라벨-인접 추출이 구조적으로 흔들린다
#   (실측 20230809800003: `계약금액(원)` 뒤 첫 숫자가 "2. 계약내역"의 2 → amt=2).
#   구판은 이 오값을 조용히 OK 로 기록했다. 아래 교차표가 그 표면 크기를 노출한다.
if (length(audit)) {
  A <- rbindlist(audit, fill = TRUE)
  cat("\n[reg] ratio_check × is_correction 교차표:\n")
  print(dcast(A[, .N, by = .(is_correction, ratio_check)], is_correction ~ ratio_check,
              value.var = "N", fill = 0))
  sus <- A[ratio_check == "MISMATCH" & is_correction == FALSE]
  cat(sprintf("[reg] 비정정 MISMATCH = %d건 (신호 패널에 실제로 들어가는 행)\n", nrow(sus)))
  if (nrow(sus)) print(head(sus[order(contract_amount)], 15))
  fwrite(A, file.path(ROOT, sprintf(".cache/dart/contract_integrity_%s_%s.csv", START, END)))
}

OUTF <- file.path(ROOT, sprintf(".cache/dart/contract_regression_%s_%s.csv", START, END))

# ── ① 정본 판정: v2(핀) vs v3 ────────────────────────────────────────────────
cat("\n[reg] ── 정본 회귀축: v2(", V2_PIN, ") vs v3, 동일 바이트 ──\n", sep = "")
regressed <- FALSE
if (is.null(V2)) {
  cat("[reg] ⚠ 미측정 — v2 핀 로드 실패. 이 실행은 회귀를 **판정하지 않았다**\n")
  regressed <- NA
} else if (length(v2diffs)) {
  V2D <- rbindlist(v2diffs, fill = TRUE)
  fwrite(V2D, sub("[.]csv$", "_v2diff.csv", OUTF))
  cat(sprintf("[reg] ❌ v2↔v3 불일치 %d건 (행 %d)\n", nrow(V2D), uniqueN(V2D$rcept_no)))
  print(V2D[, .N, by = field][order(-N)]); print(head(V2D, 20)); regressed <- TRUE
} else {
  cat(sprintf("[reg] ✅ v2↔v3 완전 일치 — %d행 × 7필드. v3 변경은 기존 경로에 무영향\n", n_done))
}

# ── ② 진단: 저장값 대조(세대 혼재를 노출한다 — 회귀 판정 아님) ─────────────────
cat("\n[reg] ── 진단축: 체크포인트 저장값 vs v3 ──\n")
if (length(diffs)) {
  DF <- rbindlist(diffs, fill = TRUE)
  fwrite(DF, OUTF)
  cat(sprintf("[reg] 저장값과 %d건 상이 (행 %d) → %s\n", nrow(DF), uniqueN(DF$rcept_no), OUTF))
  cat("     ※ 저장값은 단일 파서 산출이 아니다 — OK 행=크롤 시점 파서 / 실패 행=이후 v2 재파싱.\n")
  cat("       위 ①이 초록이면 이 차이는 **세대 차이**이지 이번 변경의 회귀가 아니다.\n")
  print(DF[, .N, by = field][order(-N)])
} else cat("[reg] 저장값과도 전량 일치\n")

# ★검증 0행을 성공으로 읽지 않는다 ("빈 결과 = 합격" 계통).
if (n_done == 0L) { cat("[reg] ⚠ 검증 0행 — 판정 불가(미측정)\n"); quit(status = 3) }
if (is.na(regressed)) quit(status = 3)
quit(status = if (isTRUE(regressed)) 1L else 0L)
