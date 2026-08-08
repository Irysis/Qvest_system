#!/usr/bin/env Rscript
## ============================================================================
## wiring_map_build.R — 표준↔소비자 배선 지도 생성기 (2026-08-08 신설, 도훈 지시)
## ----------------------------------------------------------------------------
## 왜 존재하나 — "올바른 표준이 존재하는데 소비자가 도달하지 않는다"가 **반복 계통**임이
##   2026-08-08 세션에서 실측 확인됐다(확인 7건):
##     · bootstrap 4i — scheduler_task_health.json 의 verdict 절이 있는데 원시 rc 로 재판정
##     · bootstrap §4h — stranded_repairs.json 대신 자체 좌초 로직
##     · _shared_parse.sh — resolve-only 경로가 emit 에 도달 못 해 훅 4종이 원장에서 비가시
##     · benchmark_source_parity.R — canonical_source 가 하드코딩 상수
##     · repair_rawdata_bmret_from_benchmark.R — 수리 방향이 이름에 박힘
##     · align_signal_return_ym.R — 2026-07-14 표준인데 실소비자 2개(둘 다 RAMP lane)
##     · 메모리 2건(screen_route 소비자 0 · 리더가 술어 재구현)
##
## ★정적 보고서로 만들지 않는 이유: 만든 순간부터 낡고, **낡은 지도는 "배선 완료"로 위장한다**.
##   그래서 생성기 + 정기 재생성 + **드리프트 감지(악화만 경고)** 로 만든다.
##   선례 = artifact_index.json / ARTIFACTS.md (daily_refresh 가 매일 재생성).
##
## 산출: 06_Registry/wiring_map.json   (기계용 — 판정 포함. 소비자는 재판정하지 말 것)
##       06_Registry/wiring_map_baseline.json (래칫 기준선 — 악화 판정용)
##
## 사용:
##   Rscript 02_Infrastructure/ops/wiring_map_build.R              # 생성 + 드리프트 판정
##   Rscript 02_Infrastructure/ops/wiring_map_build.R --set-baseline  # 현재 상태를 기준선으로
## exit: 0 정상 / 2 드리프트(악화) 감지
## ============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

ROOT <- Sys.getenv("QM_ROOT", "")
if (!nzchar(ROOT) || !dir.exists(file.path(ROOT, "02_Infrastructure")))
  ROOT <- tryCatch(normalizePath(getwd(), winslash = "/"), error = function(e) getwd())
setwd(ROOT)

args <- commandArgs(trailingOnly = TRUE)
SET_BASELINE <- any(args %in% c("--set-baseline", "--baseline"))

OUT_MAP  <- "06_Registry/wiring_map.json"
OUT_BASE <- "06_Registry/wiring_map_baseline.json"

## ── 표준 정의 ───────────────────────────────────────────────────────────────
## 표준 = "여러 소비자가 공유해야 하는 단일 정본". 두 부류:
##   (a) 계약/검증 헬퍼 — contracts/ · validation/ 의 최상위 함수
##   (b) 권위 판정 원장 — 06_Registry/*.json 중 판정 절(verdict/summary/canonical_*)을 가진 것
STD_DIRS <- c("02_Infrastructure/contracts", "02_Infrastructure/validation")
VERDICT_KEYS <- c("verdict", "summary", "canonical_source", "severity", "repair_directions")

## ── 스캔 범위 ───────────────────────────────────────────────────────────────
## ★.claude/worktrees 제외 — 저장소 사본 28벌이라 포함 시 스캔이 분 단위로 늘고,
##   worktree 사본의 참조는 main 배선의 증거가 아니다(오히려 과대계상).
SCAN_DIRS <- c("02_Infrastructure", "04_Research", "08_Tests", "qepm", "06_Registry",
               ".claude/skills", ".claude/agents", ".claude/rules", ".claude/commands")
SCAN_EXT  <- "\\.(R|r|py|sh|md|json)$"

collect_files <- function() {
  fs <- character(0)
  for (d in SCAN_DIRS) {
    if (!dir.exists(d)) next
    f <- list.files(d, pattern = SCAN_EXT, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    fs <- c(fs, f)
  }
  fs <- fs[!grepl("(^|/)\\.claude/worktrees/", fs)]
  fs <- fs[!grepl("(^|/)\\.git/", fs)]
  ## ★자기 자신과 자기 산출물 제외 — 안 빼면 **모든 표준이 소비자를 얻는다**.
  ##   이 생성기는 헤더 주석에 표준 파일명을 나열하고, wiring_map.json 은 전 표준명을
  ##   본문에 담는다. 실측: 제외 전 orphan 3 → 제외 안 한 채로 0 (전부 자기참조로 채워짐).
  ##   "측정 도구가 자기 측정 대상에 포함되는" 형태 — 지도가 스스로를 초록으로 만든다.
  fs <- fs[!grepl("(^|/)(wiring_map_build\\.R|wiring_map\\.json|wiring_map_baseline\\.json)$", fs)]
  unique(fs)
}

cat("[wiring] 파일 수집 중...\n")
FILES <- collect_files()
cat(sprintf("[wiring] 스캔 대상 %d 파일\n", length(FILES)))

## 파일 본문 1회만 읽는다(반복 grep 회피 — 표준 수 x 파일 수 만큼 재읽기하면 분 단위)
BODY <- vapply(FILES, function(p) {
  x <- tryCatch(readLines(p, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  paste(x, collapse = "\n")
}, character(1))
names(BODY) <- FILES

## ── (a) 헬퍼 표준 추출 ──────────────────────────────────────────────────────
std_rows <- list()
for (d in STD_DIRS) {
  if (!dir.exists(d)) next
  for (p in list.files(d, pattern = "\\.R$", full.names = TRUE)) {
    txt <- BODY[[p]]
    if (is.null(txt)) txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
    fns <- regmatches(txt, gregexpr("(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_.]*)[ \t]*<-[ \t]*function",
                                    txt, perl = TRUE))[[1]]
    fns <- sub("[ \t]*<-.*$", "", sub("^[ \t]*", "", fns))
    fns <- unique(fns[nzchar(fns) & !startsWith(fns, ".")])
    std_rows[[p]] <- data.table(standard = basename(p), kind = "helper", dir = d,
                                symbols = paste(fns, collapse = ","), n_symbols = length(fns))
  }
}

## ── (b) 권위 판정 원장 추출 ────────────────────────────────────────────────
for (p in list.files("06_Registry", pattern = "\\.json$", full.names = TRUE)) {
  j <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || !is.list(j)) next
  keys <- intersect(VERDICT_KEYS, names(j))
  if (!length(keys)) next
  std_rows[[p]] <- data.table(standard = basename(p), kind = "verdict_ledger", dir = "06_Registry",
                              symbols = paste(keys, collapse = ","), n_symbols = length(keys))
}
STD <- rbindlist(std_rows, fill = TRUE)
if (!nrow(STD)) { cat("[wiring] ★표준 0건 — 추출 실패(패턴 확인 필요)\n"); quit(status = 1L) }
cat(sprintf("[wiring] 표준 %d건 (helper %d · verdict_ledger %d)\n",
            nrow(STD), sum(STD$kind == "helper"), sum(STD$kind == "verdict_ledger")))

## ── 소비자 계수 ────────────────────────────────────────────────────────────
## 소비 = (1) 파일명 참조(source/경로) 또는 (2) 표준이 정의한 심볼 호출.
## ★자기 자신·검사기는 제외하지 않는다(검사기도 실소비자다). 단 자기 파일은 제외.
## ★2026-08-08 정정 — 심볼 매치만으로 소비자를 세면 **과대계상**된다.
##   실측(자기 검사기의 양성 대조 실패): align_signal_return_ym 은 실소비자 2개인데
##   16개로 셌다. 원인 = 이 표준이 정의한 심볼이 `ym_of`/`ym_shift` 로 **너무 일반적**이라,
##   자기 파일에 같은 이름 함수를 **직접 정의한** 무관한 코드가 전부 매치됐다.
##   (이 생성기가 진단하려던 "잘못된 것을 잼"을 스스로 재현했다.)
## ∴ 증거를 3분한다:
##   strong      = 표준 **파일 자체를 참조**(source/경로 언급) — 배선의 직접 증거
##   symbol_only = 심볼은 부르는데 파일 참조 없음 →
##       · 그 파일이 심볼을 **직접 정의**하면 = ★재구현(표준 우회, 과제 3번의 표적)
##       · 정의하지 않으면 = 전이 소비(다른 곳에서 source 된 상태) — 약한 증거
count_consumers <- function(std_file, symbols) {
  base <- basename(std_file)
  pat_file <- paste0("\\Q", base, "\\E")
  syms <- setdiff(strsplit(symbols, ",")[[1]], "")
  self <- normalizePath(std_file, winslash = "/", mustWork = FALSE)
  strong <- character(0); reimpl <- character(0); transitive <- character(0); mentions <- character(0)
  for (p in names(BODY)) {
    if (identical(normalizePath(p, winslash = "/", mustWork = FALSE), self)) next
    txt <- BODY[[p]]
    if (!nzchar(txt)) next
    ## ★배선 증거는 **실행 파일**에서만 — .json/.md 가 표준 이름을 언급하는 건 소비가 아니라
    ##   기술(記述)이다. 실측: ast_field_map_v0.json 이 align_signal_return_ym.R 을 언급해
    ##   strong 3 으로 계상됐으나 실코드 소비자는 2개였다(양성 대조로 검출).
    is_code <- grepl("\\.(R|r|py|sh)$", p)
    if (grepl(pat_file, txt, perl = TRUE)) {
      if (is_code) strong <- c(strong, p) else mentions <<- c(mentions, p)
      next
    }
    if (!is_code) next                       # 비실행 파일은 심볼 축도 보지 않는다
    if (!length(syms)) next
    called <- FALSE; defined <- FALSE
    for (s in syms) {
      if (!called && grepl(paste0("(?<![A-Za-z0-9_.])\\Q", s, "\\E[ \t]*\\("), txt, perl = TRUE)) called <- TRUE
      if (!defined && grepl(paste0("(?m)^[ \t]*\\Q", s, "\\E[ \t]*(<-|=)[ \t]*function"), txt, perl = TRUE)) defined <- TRUE
      if (called && defined) break
    }
    if (!called) next
    if (defined) reimpl <- c(reimpl, p) else transitive <- c(transitive, p)
  }
  list(strong = strong, reimpl = reimpl, transitive = transitive, mentions = mentions)
}

cat("[wiring] 소비자 계수 중...\n")
res <- vector("list", nrow(STD))
for (i in seq_len(nrow(STD))) {
  sp <- file.path(STD$dir[i], STD$standard[i])
  cc <- count_consumers(sp, STD$symbols[i])
  cons <- cc$strong                              # ★배선 판정은 strong 만으로 한다
  zone_of <- function(v) ifelse(grepl("^08_Tests/", v), "tests",
             ifelse(grepl("^02_Infrastructure/ramp/", v), "ramp",
             ifelse(grepl("^02_Infrastructure/", v), "infra",
             ifelse(grepl("^04_Research/", v), "research",
             ifelse(grepl("^qepm/", v), "qepm", "other")))))
  zone <- zone_of(cons)
  nz <- table(zone)
  n_nontest <- sum(zone != "tests")
  res[[i]] <- data.table(
    standard = STD$standard[i], kind = STD$kind[i], dir = STD$dir[i],
    n_symbols = STD$n_symbols[i],
    n_consumers = length(cons), n_consumers_nontest = n_nontest,
    n_reimpl = length(cc$reimpl),                # ★표준을 안 부르고 같은 심볼을 직접 정의 = 재구현
    n_transitive = length(cc$transitive), n_mentions = length(cc$mentions),
    zones = paste(sprintf("%s:%d", names(nz), as.integer(nz)), collapse = " "),
    consumers = paste(head(cons, 40), collapse = ";"),
    reimplementers = paste(head(cc$reimpl, 20), collapse = ";")
  )
}
W <- rbindlist(res, fill = TRUE)

## ── 판정 ───────────────────────────────────────────────────────────────────
## ★판정을 원장에 적는다 — 소비자(부팅 등)가 원시 수치로 재판정하지 않게(사례 1·2 가 그 실패).
W[, status := fifelse(n_consumers_nontest == 0L, "orphan",
              fifelse(n_consumers_nontest <= 2L, "thin", "wired"))]
## 단일 lane 국소 배선 — align_signal_return_ym 이 정확히 이 형태였다(소비자 2개 전부 ramp)
W[, single_zone := {
  z <- gsub(":[0-9]+", "", zones)
  zs <- lapply(strsplit(z, " "), function(v) setdiff(v, c("tests", "")))
  vapply(zs, function(v) length(v) == 1L, logical(1))
}]
setorder(W, n_consumers_nontest, standard)

out <- list(
  `_doc` = paste0("표준↔소비자 배선 지도. 생성기 02_Infrastructure/ops/wiring_map_build.R. ",
                  "status: orphan=비검사 소비자 0(표준이 아무도 안 씀) / thin=1~2(국소) / wired=3+. ",
                  "single_zone=TRUE 면 소비자가 한 lane 에만 있음(범용 표준인데 국소 배선 = 미배선 후보). ",
                  "★판정은 이 원장이 권위다 — 소비자는 n_consumers 로 재판정하지 말 것."),
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  scan_files = length(FILES),
  scan_dirs = SCAN_DIRS,
  summary = list(
    n_standards = nrow(W),
    orphan = sum(W$status == "orphan"),
    thin = sum(W$status == "thin"),
    wired = sum(W$status == "wired"),
    single_zone_nonorphan = sum(W$single_zone & W$status != "orphan"),
    with_reimplementers = sum(W$n_reimpl > 0L)
  ),
  standards = lapply(seq_len(nrow(W)), function(i) as.list(W[i]))
)

## ── 드리프트 판정 (래칫: 악화만 경고) ──────────────────────────────────────
drift <- list()
if (!SET_BASELINE && file.exists(OUT_BASE)) {
  b <- tryCatch(fromJSON(OUT_BASE, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.null(b) && !is.null(b$standards)) {
    B <- as.data.table(b$standards)
    M <- merge(W[, .(standard, n_consumers_nontest, status)],
               B[, .(standard, base_n = n_consumers_nontest, base_status = status)],
               by = "standard", all = TRUE)
    dec <- M[!is.na(base_n) & !is.na(n_consumers_nontest) & n_consumers_nontest < base_n]
    newstd <- M[is.na(base_n)]
    if (nrow(dec)) drift$consumers_decreased <-
      lapply(seq_len(nrow(dec)), function(i) as.list(dec[i]))
    if (nrow(newstd)) drift$new_standards <-
      lapply(seq_len(nrow(newstd)), function(i) as.list(newstd[i]))
  }
}
out$drift <- drift

dir.create(dirname(OUT_MAP), showWarnings = FALSE, recursive = TRUE)
write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null"), OUT_MAP)
if (SET_BASELINE) {
  write(toJSON(list(generated_at = out$generated_at,
                    standards = lapply(seq_len(nrow(W)), function(i)
                      as.list(W[i, .(standard, n_consumers_nontest, status)]))),
               auto_unbox = TRUE, pretty = TRUE), OUT_BASE)
  cat(sprintf("[wiring] 기준선 갱신 → %s\n", OUT_BASE))
}

cat(sprintf("[wiring] 표준 %d · orphan %d · thin %d · wired %d · 단일lane %d → %s\n",
            nrow(W), out$summary$orphan, out$summary$thin, out$summary$wired,
            out$summary$single_zone_nonorphan, OUT_MAP))
if (length(drift$consumers_decreased))
  cat(sprintf("[wiring] ★드리프트 — 소비자 감소 %d건 (표준 우회 시작 의심)\n",
              length(drift$consumers_decreased)))
if (length(drift$new_standards))
  cat(sprintf("[wiring] 신규 표준 %d건 — 배선 여부 확인 필요\n", length(drift$new_standards)))

quit(status = if (length(drift$consumers_decreased)) 2L else 0L)
