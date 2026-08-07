#!/usr/bin/env Rscript
## ============================================================================
## pg2_coherence_check.R — PG2 정체성 정합 검사 (도훈 지시 2026-08-08)
##
## 지시: "새로운 PG2가 등장할 때마다 Qvest가 조회·참조하는 PG2 정보들도 한꺼번에
##        업데이트되게 배선해줘. 과거 잔재들 때문에 시스템이 혼란스러워지는 것 같다."
##
## 설계 결정 — **새 SOT 를 만들지 않는다.**
##   PG2 정체성이 이미 두 곳(admitted_ids / current_pg2_official_name)에 적혀 갈라졌고,
##   그게 이번 사고의 원인이다. 세 번째 권위를 만들면 갈라질 곳만 는다.
##   권위는 하나 — `qepm/mailbox/governor/book_state.json::admitted_ids` (자본 게이트 SOT).
##   본 검사기는 **권위를 복제하지 않고**, 권위를 주장하는 다른 지점들이 그와 일치하는지만 본다.
##
## 실사고 (2026-08-08, 도훈 적발):
##   Σ-가중 A/B 배터리가 캐리어 `STR_1715_AR_on_M4_R05_overlay_PG2`(2-1, 2026-06-18 빌드)를
##   기준선으로 썼는데, admitted_ids 는 이미 `STR_1715_on_M4gAE_R05_noLayer4_PG2`(2-4,
##   오토인코더 + Layer4 제거)였다. Layer4/overlay 는 2026-07-02 도훈 FINAL 로 제거된 구성이다.
##   → 배터리는 **퇴역한 책**을 incumbent 로 놓고 7주간 ΔIR 을 보고했다
##     (배터리 strategy 팔 1.077 vs 실제 incumbent_book_ir 1.416).
##   ★기전: `current_pg2_official_name` 이 stale 인데 정합 검사가 없어서, 캐리어 빌더가
##     그 stale 필드를 따라갔다. **정체성이 두 곳에 적히면 반드시 갈라진다.**
##   ★resolve_admitted_slot.R(2026-08-01 신설)이 정답 배관인데 리서치·측정 레인이 안 쓴다 —
##     "소비자가 자기 술어를 되살린" 부류. 그래서 **우회 census** 를 검사 항목에 넣는다.
##
## 검사 5축
##   C1 book_state 내부 정합 : current_pg2_official_name ↔ admitted_ids
##   C2 캐리어 정체성        : carrier_meta.json::strategy ∈ admitted_ids
##   C3 캐리어 시점          : carrier_meta.json::book_state_updated_at ≥ book_state::updated_at
##   C4 생성기 핀            : generator_pins.json 키 ↔ admitted_ids
##   C5 우회 census          : PG2 id/슬롯 경로를 하드코딩하면서 resolve_admitted_slot 을
##                             참조하지 않는 실행 코드(.R/.sh/.py)
##
## 차단하지 않는다 — 진단·보고 도구다. 자본 게이트가 아니며 book_state 를 쓰지 않는다.
## 사용: Rscript 02_Infrastructure/portfolio/pg2_coherence_check.R   (exit 1 = 불일치 존재)
## ============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

.pg2_root <- function() {
  .marker <- file.path("02_Infrastructure", "portfolio", "pg2_coherence_check.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  if (file.exists(.marker)) return(getwd())
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
}

## C5 허용목록 — 역사 기록·본인 정의는 하드코딩이 정상이다.
##   ★허용은 **사유와 함께** 적는다. 사유 없는 허용목록은 검사를 조용히 죽인다.
PG2_BYPASS_ALLOW <- list(
  "02_Infrastructure/portfolio/resolve_admitted_slot.R"   = "resolver 본인",
  "02_Infrastructure/ops/resolve_admitted_slot.sh"        = "resolver 본인(shell 판)",
  "02_Infrastructure/portfolio/pg2_coherence_check.R"     = "본 검사기",
  "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R"= "generator_pins 로 sha1 고정된 미러 — 핀이 정체성 계약",
  "02_Infrastructure/portfolio/measurement_basis_audit.R" = "계보 별칭 이력(v1.10~v1.12 주석) — 역사 기록"
)

pg2_coherence_check <- function(root = .pg2_root(), quiet = FALSE) {
  say <- function(...) if (!quiet) cat(sprintf(...))
  findings <- list(); add <- function(code, sev, msg, detail = NULL)
    findings[[length(findings) + 1L]] <<- list(code = code, severity = sev, message = msg, detail = detail)

  bs_p <- file.path(root, "qepm/mailbox/governor/book_state.json")
  if (!file.exists(bs_p)) {
    add("C0", "BLOCKED", "book_state.json 부재 — 권위를 읽을 수 없어 전 축 판정 불가")
    return(list(ok = FALSE, findings = findings))
  }
  bs <- fromJSON(bs_p, simplifyVector = FALSE)
  ## ★키 접근 — grep 하면 admitted_ids_prior_* 형제 키가 섞인다(resolve_admitted_slot.R 교훈)
  admit <- unlist(bs[["admitted_ids"]] %||% list(), use.names = FALSE)
  admit <- admit[!is.na(admit) & nzchar(admit)]
  bs_at <- as.character(bs[["updated_at"]] %||% NA)
  if (!length(admit)) {
    add("C0", "BLOCKED", "admitted_ids 비어 있음 — 권위 부재")
    return(list(ok = FALSE, findings = findings))
  }
  say("[pg2] 권위 admitted_ids = %s  (book_state updated_at=%s)\n", paste(admit, collapse = ", "), bs_at)

  ## ── C1: book_state 내부 정합 ──────────────────────────────────────────────
  off <- as.character(bs[["current_pg2_official_name"]] %||% NA)
  if (is.na(off)) add("C1", "WARN", "current_pg2_official_name 부재")
  else {
    ## 공식명은 뒤에 설명이 붙으므로 **선두 토큰**이 admitted id 와 일치해야 한다
    off_id <- sub("[ (].*$", "", trimws(off))
    if (!(off_id %in% admit))
      add("C1", "MISMATCH",
          sprintf("book_state 내부 불일치: current_pg2_official_name='%s' 이나 admitted_ids=%s",
                  off_id, paste(admit, collapse = ", ")),
          "★이번 사고의 근원. 정체성이 같은 파일 안 두 필드에 적혀 갈라졌고, 캐리어 빌더가 stale 한 쪽을 따라갔다.")
    else say("[pg2] C1 OK — current_pg2_official_name 일치\n")
  }

  ## ── C2/C3: 캐리어 ─────────────────────────────────────────────────────────
  cm_p <- file.path(root, "06_Registry/book_carrier/carrier_meta.json")
  if (!file.exists(cm_p)) add("C2", "WARN", "carrier_meta.json 부재 — 캐리어 정체성 미검증")
  else {
    cm <- fromJSON(cm_p, simplifyVector = FALSE)
    cstrat <- as.character(cm[["strategy"]] %||% NA)
    if (!(cstrat %in% admit))
      add("C2", "MISMATCH",
          sprintf("캐리어가 구 PG2: strategy='%s' ∉ admitted_ids", cstrat),
          "배터리(auto_sigma_weighting_ab.R)의 기준선이 현 incumbent 가 아니다. 이 캐리어로 산출된 ΔIR 은 §7b 위반 — 채택 근거 사용 금지. 조치: book_carrier_sources.json 갱신 후 캐리어 재빌드.")
    else say("[pg2] C2 OK — 캐리어 정체성 일치\n")
    c_at <- as.character(cm[["book_state_updated_at"]] %||% NA)
    if (!is.na(c_at) && !is.na(bs_at) && substr(c_at, 1, 10) < substr(bs_at, 1, 10))
      add("C3", "MISMATCH",
          sprintf("캐리어 시점 낙후: 캐리어 기준 %s < book_state %s", substr(c_at, 1, 10), substr(bs_at, 1, 10)))
    else if (!is.na(c_at)) say("[pg2] C3 OK — 캐리어 시점 %s\n", substr(c_at, 1, 10))
  }

  ## ── C4: 생성기 핀 ─────────────────────────────────────────────────────────
  gp_p <- file.path(root, "02_Infrastructure/ops/generator_pins.json")
  if (file.exists(gp_p)) {
    gp <- fromJSON(gp_p, simplifyVector = FALSE)
    keys <- setdiff(names(gp), "_readme")
    orphan <- setdiff(keys, admit)
    if (length(orphan))
      add("C4", "WARN", sprintf("generator_pins 에 non-admitted 키: %s", paste(orphan, collapse = ", ")),
          "구 PG2 핀이 남아 있다. 퇴역 확정이면 제거, 아니면 사유 주석.")
    if (!any(admit %in% keys))
      add("C4", "MISMATCH", sprintf("현 admitted id 의 생성기 핀 부재: %s", paste(admit, collapse = ", ")))
    else if (!length(orphan)) say("[pg2] C4 OK — 생성기 핀 일치\n")
  }

  ## ── C5: 우회 census ───────────────────────────────────────────────────────
  ## PG2 id / 슬롯 경로를 하드코딩하면서 resolver 를 참조하지 않는 실행 코드.
  ## ★"소비자가 자기 술어를 되살린" 상태는 다른 어떤 검사에도 안 보인다.
  code <- list.files(file.path(root, "02_Infrastructure"), pattern = "[.](R|sh|py)$",
                     full.names = TRUE, recursive = TRUE)
  pat_id   <- "STR_1715[A-Za-z0-9_]*_PG2"
  pat_slot <- "05_Production/2[.]Factor_Model/[0-9]+-[0-9]+"
  bypass <- character(0)
  for (f in code) {
    ## ★경로 상대화는 정규식으로 하지 않는다 — 루트에 정규식 메타문자가 있으면 패턴이 깨진다
    ##   (실측: Windows 경로 이스케이프가 TRE 에서 'Invalid contents of {}' 로 컴파일 실패).
    ##   문자열 접두 제거로 충분하고 안전하다.
    fp  <- normalizePath(f, winslash = "/", mustWork = FALSE)
    rel <- if (startsWith(fp, paste0(root, "/"))) substring(fp, nchar(root) + 2L) else fp
    if (rel %in% names(PG2_BYPASS_ALLOW)) next
    txt <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    if (!length(txt)) next
    hard <- any(grepl(pat_id, txt)) || any(grepl(pat_slot, txt))
    if (!hard) next
    if (any(grepl("resolve_admitted_slot", txt, fixed = TRUE))) next   # resolver 사용 = 정상
    bypass <- c(bypass, rel)
  }
  if (length(bypass))
    add("C5", "WARN", sprintf("resolver 우회 실행코드 %d건 — PG2 교체 시 함께 안 바뀐다", length(bypass)),
        paste(bypass, collapse = "\n      "))
  else say("[pg2] C5 OK — 우회 코드 없음\n")

  mism <- Filter(function(x) x$severity %in% c("MISMATCH", "BLOCKED"), findings)
  if (!quiet) {
    if (!length(findings)) cat("[pg2] 전 축 OK\n")
    for (x in findings) {
      cat(sprintf("[pg2] %s %s: %s\n", x$severity, x$code, x$message))
      if (!is.null(x$detail)) cat(sprintf("      %s\n", x$detail))
    }
    if (length(mism))
      cat(sprintf("\n[pg2] ★불일치 %d건 — 새 PG2 등재 후 함께 갱신되지 않은 참조가 있다.\n", length(mism)))
  }
  list(ok = length(mism) == 0L, admitted_ids = admit, findings = findings)
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

if (sys.nframe() == 0L && identical(basename(sub("^--file=", "",
      commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1])),
      "pg2_coherence_check.R")) {
  r <- pg2_coherence_check()
  quit(status = if (isTRUE(r$ok)) 0L else 1L)
}
