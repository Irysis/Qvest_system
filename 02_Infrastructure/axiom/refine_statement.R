# refine_statement.R — 공리 statement 결정적 정제기 + 활성화 게이트 R0~R6
#   (v9.1 "결합 층 개방" 커밋13, 2026-08-23 — 승인 플랜 §7-S4a)
#
# 왜 있는가
# ---------
# `cluster_extractor._draft_statement`(:249-265)가 family·tags·건수만 f-string 으로 이어
#   "[방법론 조건부 규칙 초안] family=momentum, tags=..., supporting=187건 L-code."
# 를 만든다. 이건 **클러스터의 메타데이터**이지 규칙이 아니다. 사람 승인을 없애려면
# (E-1) 승인이 하던 일 — "이 문장이 대전제로 설 자격이 있는가" — 을 기계가 해야 한다.
#
# ★LLM 을 쓰지 않는다. 원료가 이미 구조화 필드로 있다:
#   후보/공리 JSON : mechanism.economic_explanation(실측 103~508자) · evidence.constructions[]
#                    · falsification.attempts[]{test,result,effect_retained,detail} · oos_validation
#   .cache/lcode_corpus.json : grade · record_type · tags · fmt_codes · construction_type
#                    · metric_type · selection_type · next_probe · live_trigger
#   ⇒ 조립은 결정적이어야 한다. 같은 입력에 같은 문장이 나오지 않으면 `refine_input_sha`
#     기반 재시도·held_stale 회계가 성립하지 않는다.
#
# 파이프라인 (§7-S4a)
#   S0 타입 정규화 → S1 멤버 해결 → S2 win/loss 팔 분리 → S3 범위절 → S4 판별 토큰
#   → S5 메커니즘절 → S6 증거절(+반증 결산) → S7 부활/반증 조건절 → S8 산출 2종
#
# ★S0 없이는 죽는다(실측): corpus `tags` = list 461 / str 81(';' 구분),
#   `next_probe` = str 159 / list 75 / dict 3, `mechanism_hypothesis` = str 313 / dict 1.
#   정규화 없이 strsplit/`[[` 하면 문자 단위로 쪼개져 `tag:,` 같은 쓰레기 토큰이 나온다.
#
# ★S3 범위절에 **고정 축 7종(long-only·≤25종·K200∪KQ150·15bps·[0,0.20]·Σw=1·PIT)을
#   절대 넣지 않는다** — INV-7 제약 방화벽. 제약은 문제의 정의이지 규칙의 조건이 아니고,
#   공리가 제약을 조건절로 인용하면 다음 라운드가 "그 제약을 풀면?"을 레버로 읽는다.
#
# ★S6 반증 결산은 **문장의 필수 구성요소**다. 활성화 예상 5건 중 AX-AS-001 은 반증 116건
#   중 42건이 falsified, AX-RAMP-005/006 도 9/23·7/20 이다. 결산을 강제하지 않으면
#   자기 증거가 반증한 규칙을 대전제로 광고하게 된다.
#
# 활성화 게이트 R0~R6 (전부 통과 = REFINED / 하나라도 미충족 = HELD)
#   R0 선언 polarity == 현 corpus 재계산 polarity
#   R1 멤버 결측 <= 0.20
#   R2 판별 토큰 >= 1 (동어반복 토큰 제외)
#   R3 mechanism_type != unknown ∧ explanation >= 40자 ∧ 보일러플레이트 아님
#   R4 falsification.attempts >= 1
#   R5 멤버에 next_probe / live_trigger >= 1
#   R6 같은 (mode, family, polarity, type) 키의 다른 active/proposed 와 supporting Jaccard < 0.5
# ★promote.R:74 의 **채점 hurdle 은 건드리지 않는다** — R0~R6 는 *활성화* 게이트다.
#   그래야 promote.R verdict 의미론과 test_promotion_ladder_dryrun.py [B]① 이 살아 있다.
#   v9 가 falsification 을 hurdle 에서 뺐기 때문에 R4 가 그 자리를 메운다.
#
# 실패 = 영구 SKIP 없음(AX-000). refine_input_sha 를 기록하고, 입력이 바뀌면 자동 재시도.
#   동일 sha 로 8주 연속 HELD 면 status="held_stale" — **삭제는 하지 않는다**.
#
# Usage
#   Rscript 02_Infrastructure/axiom/refine_statement.R --preview --all
#   Rscript 02_Infrastructure/axiom/refine_statement.R --preview <axiom_or_candidate.json>
#   Rscript 02_Infrastructure/axiom/refine_statement.R --backfill [--dry-run]
#   (promote.R 에서는 sys.source 로 적재 후 refine_statement(candidate, corpus, fals_norm=))
suppressPackageStartupMessages({ library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.rs_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "")),
             Sys.getenv("QVEST_PROJECT_DIR", ""), Sys.getenv("PROJECT_ROOT", ""), getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

.RS <- list(
  lift_min        = 0.34,   # |P(t|win) - P(t|loss)| 하한
  arm_support_min = 2L,     # 우세 팔에서의 최소 등장 건수
  miss_max        = 0.20,   # R1 멤버 결측 상한
  jaccard_max     = 0.5,    # R6 중복 상한
  mech_expl_min   = 40L,    # R3 explanation 최소 길이
  stmt_max        = 600L,   # S8 statement 상한
  inject_max      = 70L,    # S8 statement_inject 상한 (주입 렌더 ML_LINE_MAX 와 동일)
  held_stale_wk   = 8L,     # 동일 sha 연속 HELD → held_stale
  max_tokens_shown = 3L
)

# 보일러플레이트 = "메커니즘 자리에 놓인 자리표시자". 실측 18건에서 오탐 0을 확인했다
#   (전건 economic_explanation 103~508자, 아래 패턴 히트 0).
.RS_BOILERPLATE <- paste(c(
  "\\[[^]]*\ucd08\uc548[^]]*\\]",          # [.. 초안 ..]
  "\ud655\uc815\\s*\ud544\uc694",           # 확정 필요
  "\ubbf8\uae30\ub85d",                      # 미기록
  "\uae30\ub85d\\s*\uc5c6\uc74c",           # 기록 없음
  "evidence_draft",
  "promote\\.R\\s*5\ucd95\\s*\uac80\uc99d",  # promote.R 5축 검증
  "^\\s*(N/A|NA|TBD|null|NULL|none|None)\\s*$"
), collapse = "|")

# ── S0: 타입 정규화 ─────────────────────────────────────────────────────────
# .rs_tokens : 태그류 — 구분자(';' ',' '|') 로 쪼갠다.
# .rs_lines  : 문장류(next_probe/live_trigger) — **쪼개지 않는다**(쉼표가 문장 안에 있다).
# 둘 다 str / list / list-of-dict / dict 전부 수용. 실패는 character(0) 이지 crash 아님.
.rs_flatten <- function(x, depth = 0L) {
  if (is.null(x) || !length(x) || depth > 4L) return(character(0))
  if (is.character(x)) return(trimws(x))
  if (is.list(x)) {
    out <- character(0)
    for (e in x) out <- c(out, .rs_flatten(e, depth + 1L))
    return(out)
  }
  if (is.atomic(x)) return(trimws(as.character(x)))
  character(0)
}
.rs_lines <- function(x) {
  v <- .rs_flatten(x)
  v <- v[nzchar(v) & !(tolower(v) %in% c("na", "null", "none", "-"))]
  unname(v)
}
.rs_tokens <- function(x) {
  v <- .rs_lines(x)
  if (!length(v)) return(character(0))
  v <- unlist(strsplit(v, "[;,|]"), use.names = FALSE)
  v <- trimws(v)
  unname(v[nzchar(v)])
}
.rs_txt1 <- function(x, default = "") {
  v <- .rs_lines(x)
  if (!length(v)) return(default)
  gsub("[\r\n\t]+", " ", v[1])
}

# 후보(*_draft) / 공리(평문) 양쪽 스키마를 같은 이름으로 읽는다.
#   promote.R 은 candidate 를, --preview/--backfill 은 active/modes/** 공리를 넘긴다.
.rs_get <- function(obj, ...) {
  for (k in c(...)) {
    v <- obj[[k]]
    if (!is.null(v) && length(v)) return(v)
  }
  NULL
}
.rs_input <- function(obj) {
  list(
    id        = as.character(.rs_get(obj, "axiom_id", "candidate_id", "id") %||% "?")[1],
    mode      = as.character(.rs_get(obj, "research_mode") %||% "qepm_legacy")[1],
    polarity  = as.character(.rs_get(obj, "polarity") %||% "unknown")[1],
    type      = as.character(.rs_get(obj, "type", "axiom_class") %||% "empirical")[1],
    ckey      = as.character(.rs_get(obj, "cluster_key") %||% "")[1],
    stmt_in   = as.character(.rs_get(obj, "statement_draft", "statement", "text") %||% "")[1],
    sup       = unique(as.character(.rs_flatten(.rs_get(obj, "supporting_l_codes")))),
    scope     = .rs_get(obj, "scope_draft", "scope") %||% list(),
    evidence  = .rs_get(obj, "evidence_draft", "evidence") %||% list(),
    fals      = .rs_get(obj, "falsification_draft", "falsification") %||% list(),
    mech      = .rs_get(obj, "mechanism_draft", "mechanism") %||% list(),
    oos       = .rs_get(obj, "oos_validation_draft", "oos_validation") %||% list()
  )
}

.rs_sha1 <- function(txt) {
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(txt, algo = "sha1", serialize = FALSE))
  if (requireNamespace("openssl", quietly = TRUE))
    return(as.character(openssl::sha1(charToRaw(enc2utf8(txt)))))
  substr(paste0("nohash", nchar(txt)), 1, 12)
}

.rs_index_corpus <- function(corpus) {
  lst <- corpus$lcodes %||% list()
  idx <- new.env(parent = emptyenv(), hash = TRUE, size = max(64L, length(lst)))
  for (i in seq_along(lst)) {
    k <- as.character(lst[[i]]$l_code %||% "")[1]
    if (nzchar(k) && !exists(k, envir = idx, inherits = FALSE)) assign(k, lst[[i]], envir = idx)
  }
  idx
}
.rs_load_corpus <- function(root) {
  cp <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(cp)) stop("lcode_corpus.json 없음 — lcode_harvester.py 먼저 실행")
  fromJSON(cp, simplifyVector = FALSE)
}

# grade → 방향. promote.R::.grade_direction 과 **같은 규약**이어야 한다(win/loss 사다리 정합).
.rs_grade_direction <- function(g) {
  g <- toupper(as.character(g %||% "")[1])
  if (is.na(g) || !nzchar(g)) return(NA_character_)
  if (g %in% c("A", "B") || startsWith(g, "A_") || g == "B_ARCHIVE") return("win")
  if (g %in% c("C", "F", "REJECT")) return("loss")
  NA_character_
}

.rs_pol_family <- function(p) {
  p <- tolower(as.character(p %||% "unknown")[1])
  if (identical(p, "positive")) return("positive")
  if (identical(p, "negative")) return("negative")
  if (p %in% c("conditional", "mixed")) return("two_armed")
  "unknown"
}
# R0 재계산 — 선언이 아니라 **현 corpus 의 grade 분포**가 방향을 정한다.
#   AX-AR-001/003 이 polarity="positive"(성공 규칙)인데 supporting performance grade 에
#   A 가 0건(AR-001: C1/F4/B1)인 화석 후보를 잡는 축이 이것이다.
.rs_recompute_polarity <- function(n_win, n_loss) {
  if (n_win >= 2L && n_loss >= 2L) return("two_armed")
  if (n_win >= 2L && n_loss <  2L) return("positive")
  if (n_loss >= 2L && n_win  <  2L) return("negative")
  "unknown"
}

.rs_pol_label <- function(fam) {
  switch(fam, positive = "\uc131\ub9bd \uaddc\uce59",      # 성립 규칙
              negative = "\uae30\uac01 \uaddc\uce59",      # 기각 규칙
              two_armed = "\uc870\uac74\ubd80 \uaddc\uce59", # 조건부 규칙
              "\ubbf8\uc0c1 \uaddc\uce59")                  # 미상 규칙
}

# ── S4: 판별 토큰 ───────────────────────────────────────────────────────────
# 토큰 = tags ∪ fmt_codes ∪ construction_type ∪ metric_type ∪ selection_type.
#   family 는 넣지 않는다 — 범위절(S3)이 이미 말한 것을 판별 토큰이라 부르면 동어반복이다.
#   모드 태그(ALPHA_SEARCH 등)도 같은 이유로 제외.
.rs_member_tokens <- function(rec, stop_lower) {
  t <- character(0)
  for (x in .rs_tokens(rec$tags))      t <- c(t, paste0("tag:", toupper(x)))
  for (x in .rs_tokens(rec$fmt_codes)) t <- c(t, paste0("fmt:", toupper(x)))
  for (kv in list(c("construction_type", "constr"), c("metric_type", "metric"),
                  c("selection_type", "sel"))) {
    v <- .rs_txt1(rec[[kv[1]]], "")
    if (nzchar(v) && !(tolower(v) %in% c("unknown", "na", "none"))) t <- c(t, paste0(kv[2], ":", tolower(v)))
  }
  t <- unique(t)
  t[!(tolower(t) %in% stop_lower)]
}

.rs_discriminative <- function(win_recs, loss_recs, stop_lower) {
  nw <- length(win_recs); nl <- length(loss_recs)
  cw <- list(); cl <- list()
  bump <- function(acc, toks) { for (t in toks) acc[[t]] <- (acc[[t]] %||% 0L) + 1L; acc }
  for (r in win_recs)  cw <- bump(cw, .rs_member_tokens(r, stop_lower))
  for (r in loss_recs) cl <- bump(cl, .rs_member_tokens(r, stop_lower))
  keys <- unique(c(names(cw), names(cl)))
  out <- list()
  for (k in keys) {
    a <- as.integer(cw[[k]] %||% 0L); b <- as.integer(cl[[k]] %||% 0L)
    pw <- if (nw) a / nw else 0; pl <- if (nl) b / nl else 0
    lift <- pw - pl
    fav <- if (lift > 0) "win" else "loss"
    sup <- if (lift > 0) a else b
    if (abs(lift) >= .RS$lift_min && sup >= .RS$arm_support_min)
      out[[length(out) + 1L]] <- list(token = k, lift = round(lift, 3), favors = fav,
                                      n_win = a, n_loss = b, support = sup)
  }
  if (length(out)) out <- out[order(-vapply(out, function(z) abs(z$lift), numeric(1)))]
  out
}

.rs_tok_phrase <- function(d) {
  sprintf("%s%s%s(lift %+.2f, n=%d)", d$token,
          " \u2192 ", if (identical(d$favors, "win")) "win" else "loss", d$lift, d$support)
}

# ── S6: 반증 결산 (.fals_norm_result 재사용) ────────────────────────────────
# promote.R:309-317 이 정본이다. 여기서 재구현하면 토큰 정규화가 두 벌이 되고,
#   한쪽만 고쳐졌을 때 어느 검사에도 안 보인다(이 저장소의 반복 실패 계통).
.rs_resolve_fals_norm <- function(fals_norm = NULL, root = NULL) {
  if (is.function(fals_norm)) return(fals_norm)
  pr <- file.path(root %||% .rs_root(), "02_Infrastructure", "axiom", "promote.R")
  if (file.exists(pr)) {
    got <- tryCatch({
      had <- Sys.getenv("PROMOTE_SOURCED", NA_character_)
      Sys.setenv(PROMOTE_SOURCED = "1")
      on.exit(if (is.na(had)) Sys.unsetenv("PROMOTE_SOURCED") else Sys.setenv(PROMOTE_SOURCED = had),
              add = TRUE)
      e <- new.env(parent = globalenv())
      suppressWarnings(suppressMessages(capture.output(sys.source(pr, envir = e))))
      if (exists(".fals_norm_result", envir = e, mode = "function")) e$.fals_norm_result else NULL
    }, error = function(err) NULL)
    if (is.function(got)) return(got)
  }
  # 최후 폴백 — 정본을 못 읽었다는 사실을 산출물에 남긴다(조용한 분기 금지).
  attr_fn <- function(res) {
    s <- tolower(trimws(as.character(res %||% "")[1]))
    if (is.na(s) || !nzchar(s)) return("unknown")
    if (grepl("falsif", s, fixed = TRUE) || identical(s, "negative")) return("falsified")
    if (grepl("surviv", s, fixed = TRUE) || identical(s, "passed")) return("survived")
    if (grepl("weaken", s, fixed = TRUE)) return("weakened")
    if (identical(s, "diagnostic")) return("diagnostic")
    "unknown"
  }
  attr(attr_fn, "rs_fallback") <- TRUE
  attr_fn
}

.rs_falsification_ledger <- function(fals, fnorm) {
  att <- fals$attempts %||% list()
  if (is.character(att)) att <- as.list(att)
  n <- length(att)
  structured <- Filter(function(a) is.list(a), att)
  toks <- vapply(structured, function(a) as.character(a$result %||% "")[1], character(1))
  norm <- if (length(toks)) vapply(toks, fnorm, character(1), USE.NAMES = FALSE) else character(0)
  list(n = n,
       n_structured = length(structured),
       n_falsified = sum(norm == "falsified"),
       n_survived  = sum(norm == "survived"),
       n_weakened  = sum(norm == "weakened"),
       n_diagnostic = sum(norm == "diagnostic"),
       n_unknown   = sum(norm == "unknown"),
       fallback_norm = isTRUE(attr(fnorm, "rs_fallback")))
}

.rs_first_sentence <- function(txt, maxlen) {
  s <- gsub("\\s+", " ", trimws(as.character(txt %||% "")[1]))
  if (!nzchar(s)) return("")
  if (nchar(s) <= maxlen) return(s)
  head <- substr(s, 1, maxlen)
  cut <- max(regexpr_last(head, "\\. "), regexpr_last(head, "\u2014 "), regexpr_last(head, "\uc74c\\. "))
  if (cut > maxlen * 0.5) substr(head, 1, cut) else paste0(head, "\u2026")
}
regexpr_last <- function(s, pat) {
  m <- gregexpr(pat, s, perl = TRUE)[[1]]
  if (length(m) == 1 && m[1] == -1) return(-1L)
  as.integer(m[length(m)])
}

# ── R6: 중복 비포섭 ─────────────────────────────────────────────────────────
.rs_load_peers <- function(root, self_id) {
  d <- file.path(root, "qepm", "memory", "axioms", "active", "modes")
  if (!dir.exists(d)) return(list())
  out <- list()
  for (f in list.files(d, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)) {
    a <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(a)) next
    aid <- as.character(a$axiom_id %||% sub("\\.json$", "", basename(f)))[1]
    if (identical(aid, self_id)) next
    st <- as.character(a$status %||% "active")[1]
    if (!(st %in% c("active", "proposed"))) next
    out[[length(out) + 1L]] <- a
  }
  out
}
.rs_jaccard <- function(a, b) {
  a <- unique(a); b <- unique(b)
  u <- length(union(a, b))
  if (!u) return(0)
  length(intersect(a, b)) / u
}

# ── 본체 ────────────────────────────────────────────────────────────────────
# input      : candidate(list, *_draft) 또는 axiom(list) — 파일 경로도 허용
# corpus     : fromJSON(lcode_corpus.json) — NULL 이면 root 에서 읽는다
# fals_norm  : promote.R::.fals_norm_result (권장). NULL 이면 promote.R 에서 해석
# peers      : R6 대조군. NULL 이면 active/modes/** 에서 읽는다
refine_statement <- function(input, corpus = NULL, fals_norm = NULL, peers = NULL,
                             root = NULL, verbose = FALSE) {
  root <- root %||% .rs_root()
  if (is.character(input) && length(input) == 1L && file.exists(input))
    input <- fromJSON(input, simplifyVector = FALSE)
  cand <- .rs_input(input)
  if (is.null(corpus)) corpus <- .rs_load_corpus(root)
  idx <- .rs_index_corpus(corpus)
  fnorm <- .rs_resolve_fals_norm(fals_norm, root)

  # ── S1 멤버 해결 ──
  sup <- cand$sup
  recs <- list(); missing <- character(0)
  for (lc in sup) {
    if (nzchar(lc) && exists(lc, envir = idx, inherits = FALSE)) recs[[length(recs) + 1L]] <- get(lc, envir = idx)
    else missing <- c(missing, lc)
  }
  n_sup <- length(sup)
  miss_rate <- if (n_sup) length(missing) / n_sup else 1

  # ── S2 win/loss 팔 (record_type=="performance" 만) ──
  perf <- Filter(function(r) identical(.rs_txt1(r$record_type, ""), "performance"), recs)
  dirs <- vapply(perf, function(r) .rs_grade_direction(r$grade), character(1))
  win_recs  <- perf[!is.na(dirs) & dirs == "win"]
  loss_recs <- perf[!is.na(dirs) & dirs == "loss"]
  n_win <- length(win_recs); n_loss <- length(loss_recs)

  # ── S3 범위절 (★고정 축 7종 절대 미포함 — INV-7 제약 방화벽) ──
  sc <- cand$scope
  fam    <- .rs_txt1(sc$factor_family, "")
  market <- .rs_txt1(sc$market, "")
  regime <- .rs_txt1(sc$regime, "")
  constrs <- unique(.rs_tokens(.rs_get(cand$evidence, "constructions", "construction_types")))
  constrs <- constrs[!(tolower(constrs) %in% c("unknown", "na", "none"))]
  # ★construction 실값에는 서술문 통째(200자+)가 섞여 있다(RAMP 계열 실측). 라벨로 쓰려면
  #   반드시 절단해야 한다 — 안 자르면 근거절이 600자 예산을 혼자 먹고 **반증 결산이
  #   문장에서 밀려난다**(자기 증거가 반증한 규칙을 무조건문으로 광고하는 그 실패).
  constr_lbl <- vapply(constrs, function(x) {
    x <- gsub("\\s+", " ", trimws(x))
    if (nchar(x) > 24L) paste0(substr(x, 1, 23L), "…") else x
  }, character(1), USE.NAMES = FALSE)
  scope_bits <- c(if (nzchar(market)) market,
                  if (nzchar(fam)) sprintf("%s \uacc4\uc5f4", fam),          # "<fam> 계열"
                  sprintf("%s \ubaa8\ub4dc", cand$mode),                       # "<mode> 모드"
                  if (nzchar(regime)) sprintf("\uad6d\uba74 %s", regime),      # "국면 <regime>"
                  if (length(constrs)) sprintf("\uad6c\uc131 %d\uc885", length(constrs)))
  scope_clause <- paste(scope_bits, collapse = "\u00b7")

  # ── S4 판별 토큰 ──
  stop_lower <- tolower(unique(c(paste0("tag:", toupper(fam)), paste0("tag:", fam),
                                 paste0("tag:", toupper(cand$mode)),
                                 paste0("tag:", toupper(gsub("_", "", cand$mode))),
                                 paste0("constr:", tolower(fam)),
                                 "tag:", "fmt:", "constr:", "metric:", "sel:")))
  disc <- .rs_discriminative(win_recs, loss_recs, stop_lower)
  disc_top <- head(disc, .RS$max_tokens_shown)
  disc_clause <- if (length(disc_top))
    paste(vapply(disc_top, .rs_tok_phrase, character(1)), collapse = " / ") else ""

  # ── S5 메커니즘절 ──
  mtype <- .rs_txt1(cand$mech$mechanism_type, "unknown")
  expl  <- .rs_txt1(cand$mech$economic_explanation, "")
  expl_boiler <- nzchar(expl) && grepl(.RS_BOILERPLATE, expl, perl = TRUE)
  mech_clause <- if (nzchar(expl)) sprintf("[%s] %s", mtype, .rs_first_sentence(expl, 200L)) else ""

  # ── S6 증거절 + 반증 결산 (필수) ──
  led <- .rs_falsification_ledger(cand$fals, fnorm)
  oos_med <- suppressWarnings(as.numeric(.rs_txt1(cand$oos$oos_effect_vs_is, "")))
  .ev_clause <- function(n_constr) sprintf("\uadfc\uac70: L-code %d\uac74(win %d/loss %d%s)%s",
                       n_sup, n_win, n_loss,
                       if (length(missing)) sprintf(", \uacb0\uce21 %d", length(missing)) else "",
                       if (n_constr > 0 && length(constr_lbl))
                         sprintf(" \u00b7 \uad6c\uc131 %s", paste(head(constr_lbl, n_constr), collapse = "/"))
                       else "")
  # \u2605fals_clause \ub294 \uc5b4\ub5a4 \uac10\ucd95 \ub2e8\uacc4\uc5d0\uc11c\ub3c4 **\ub4dc\ub86d \ub300\uc0c1\uc774 \uc544\ub2c8\ub2e4**(S6 \ud544\uc218 \uad6c\uc131\uc694\uc18c).
  fals_clause <- sprintf("\ubc18\uc99d %d\ud68c \u2192 falsified %d\u00b7survived %d\u00b7weakened %d",
                         led$n, led$n_falsified, led$n_survived, led$n_weakened)
  if (is.finite(oos_med))
    fals_clause <- sprintf("%s \u00b7 OOS retention %.3f", fals_clause, oos_med)

  # ── S7 부활/반증 조건절 ──
  probes <- character(0); triggers <- character(0)
  for (r in recs) {
    probes   <- c(probes, .rs_lines(r$next_probe), .rs_lines(r$next_probes))
    triggers <- c(triggers, .rs_lines(r$live_trigger))
  }
  probes <- unique(probes[nchar(probes) >= 8L])
  triggers <- unique(triggers[nchar(triggers) >= 4L])
  n_probe <- length(probes); n_trigger <- length(triggers)
  cond_bits <- c(if (n_trigger) sprintf("\ubd80\ud65c: %s", .rs_first_sentence(triggers[1], 90L)),
                 if (n_probe)   sprintf("\ub2e4\uc74c \ud0d0\uce68: %s", .rs_first_sentence(probes[1], 110L)))
  cond_clause <- paste(cond_bits, collapse = " / ")

  # ── R0~R6 ──
  pol_decl <- .rs_pol_family(cand$polarity)
  pol_calc <- .rs_recompute_polarity(n_win, n_loss)
  jac_max <- 0; jac_peer <- NA_character_
  key_self <- tolower(paste(cand$mode, fam, cand$polarity, cand$type, sep = "|"))
  if (is.null(peers)) peers <- .rs_load_peers(root, cand$id)
  for (p in peers) {
    pin <- .rs_input(p)
    # ★자기 자신 제외는 axiom_id 만으로 부족하다. promote.R 은 **candidate**(CAND_...)를 넘기는데
    #   그 candidate 가 이미 발행한 공리(AX-...)가 peers 에 있으면 Jaccard 1.0 으로 자기와
    #   중복해 R6 가 영원히 서게 된다(실측: CAND_alpha_search_482e6c939793 ↔ AX-AS-001).
    #   동일성의 정본 = cluster_key 또는 promotion.source_candidate (.promote_to_active 멱등 검사와 동일).
    if (identical(pin$id, cand$id)) next
    if (nzchar(cand$ckey) && identical(pin$ckey, cand$ckey)) next
    if (identical(as.character(p$promotion$source_candidate %||% "")[1], cand$id)) next
    kp <- tolower(paste(pin$mode, .rs_txt1(pin$scope$factor_family, ""), pin$polarity, pin$type, sep = "|"))
    if (!identical(kp, key_self)) next
    j <- .rs_jaccard(sup, pin$sup)
    if (j > jac_max) { jac_max <- j; jac_peer <- pin$id }
  }

  gates <- list(
    R0_polarity = list(pass = identical(pol_decl, pol_calc) && !identical(pol_calc, "unknown"),
                       detail = sprintf("declared=%s(%s) recomputed=%s (win %d/loss %d)",
                                        cand$polarity, pol_decl, pol_calc, n_win, n_loss)),
    R1_members  = list(pass = miss_rate <= .RS$miss_max,
                       detail = sprintf("missing %d/%d = %.3f (max %.2f)",
                                        length(missing), n_sup, miss_rate, .RS$miss_max)),
    R2_tokens   = list(pass = length(disc) >= 1L,
                       detail = sprintf("discriminative=%d (|lift|>=%.2f, arm support>=%d)",
                                        length(disc), .RS$lift_min, .RS$arm_support_min)),
    R3_mechanism = list(pass = (!identical(mtype, "unknown") && nchar(expl) >= .RS$mech_expl_min &&
                                  !expl_boiler),
                        detail = sprintf("type=%s expl=%d\uc790 boilerplate=%s", mtype, nchar(expl), expl_boiler)),
    R4_falsification = list(pass = led$n >= 1L,
                            detail = sprintf("attempts=%d (structured=%d)", led$n, led$n_structured)),
    R5_revival  = list(pass = (n_probe + n_trigger) >= 1L,
                       detail = sprintf("next_probe=%d live_trigger=%d", n_probe, n_trigger)),
    R6_distinct = list(pass = jac_max < .RS$jaccard_max,
                       detail = sprintf("max supporting Jaccard=%.3f vs %s (max %.2f)",
                                        jac_max, jac_peer %||% "-", .RS$jaccard_max))
  )
  failing <- names(gates)[!vapply(gates, function(g) isTRUE(g$pass), logical(1))]
  verdict <- if (!length(failing)) "REFINED" else "HELD"

  # ── S8 산출 2종 ──
  # 감축 사다리(결정적) = (판별토큰 n, 기전 길이, 구성 라벨 n, 조건절 on/off).
  #   ★scope 절과 fals_clause(반증 결산)는 **어느 단계에서도 빠지지 않는다**.
  #     최소 단계 예상 길이 = scope~55 + 판별~45 + 기전~90 + 근거~40 + 반증~70 = 300자 안팎.
  pol_lbl <- .rs_pol_label(pol_calc)
  .compose <- function(n_tok, mech_len, n_constr, cond_on) {
    dcl <- if (length(disc))
      paste(vapply(head(disc, n_tok), .rs_tok_phrase, character(1)), collapse = " / ") else ""
    mcl <- if (nzchar(expl)) sprintf("[%s] %s", mtype, .rs_first_sentence(expl, mech_len)) else ""
    p <- c(sprintf("[%s] %s", pol_lbl, scope_clause),
           if (nzchar(dcl)) sprintf("\ud310\ubcc4: %s", dcl),
           if (nzchar(mcl)) sprintf("\uae30\uc804: %s", mcl),
           .ev_clause(n_constr),
           fals_clause,
           if (cond_on && nzchar(cond_clause)) cond_clause)
    paste(p, collapse = " \u2014 ")
  }
  .steps <- list(c(3, 200, 3, 1), c(3, 180, 2, 1), c(2, 160, 2, 0),
                 c(2, 140, 1, 0), c(1, 110, 1, 0), c(1, 80, 0, 0))
  stmt <- ""
  for (s in .steps) {
    stmt <- .compose(as.integer(s[1]), as.integer(s[2]), as.integer(s[3]), s[4] == 1)
    if (nchar(stmt) <= .RS$stmt_max) break
  }
  if (nchar(stmt) > .RS$stmt_max) {
    # 최후 수단도 꼬리 절단이 아니라 **기전절 절단**이다 — 반증 결산을 잃지 않기 위해.
    over <- nchar(stmt) - .RS$stmt_max + 1L
    stmt <- .compose(1L, max(30L, 80L - over), 0L, FALSE)
    if (nchar(stmt) > .RS$stmt_max) stmt <- paste0(substr(stmt, 1, .RS$stmt_max - 1L), "\u2026")
  }

  inj_tok <- if (length(disc)) sprintf("%s\u2192%s", disc[[1]]$token,
                                       if (identical(disc[[1]]$favors, "win")) "win" else "loss") else "\ud310\ubcc4\ubbf8\uc0b0"
  inj <- sprintf("%s %s (L%d w%d/l%d, \ubc18\uc99d %dF/%d)",
                 if (nzchar(fam)) fam else cand$mode, inj_tok, n_sup, n_win, n_loss,
                 led$n_falsified, led$n)
  if (nchar(inj) > .RS$inject_max) inj <- substr(inj, 1, .RS$inject_max)

  sha_src <- paste(c(cand$ckey, cand$mode, cand$polarity, cand$type, fam,
                     sort(sup, method = "radix"),
                     vapply(recs, function(r) paste(.rs_txt1(r$l_code, ""), .rs_txt1(r$grade, ""),
                                                    .rs_txt1(r$record_type, ""), .rs_txt1(r$metric_type, ""),
                                                    sep = "~"), character(1)),
                     mtype, substr(expl, 1, 400), as.character(led$n)), collapse = "\x1e")

  res <- list(
    axiom_id = cand$id, cluster_key = cand$ckey, mode = cand$mode,
    verdict = verdict,
    statement = stmt, statement_inject = inj,
    refine_input_sha = .rs_sha1(sha_src),
    gates = lapply(gates, function(g) list(pass = isTRUE(g$pass), detail = g$detail)),
    failing = as.list(failing),
    diagnostics = list(
      n_supporting = n_sup, n_missing = length(missing), missing_rate = round(miss_rate, 4),
      n_performance = length(perf), n_win = n_win, n_loss = n_loss,
      polarity_declared = cand$polarity, polarity_recomputed = pol_calc,
      n_discriminative = length(disc),
      discriminative_top = lapply(disc_top, function(z) z),
      mechanism_type = mtype, mechanism_expl_chars = nchar(expl), mechanism_boilerplate = expl_boiler,
      falsification = led, n_next_probe = n_probe, n_live_trigger = n_trigger,
      max_jaccard = round(jac_max, 4), jaccard_peer = jac_peer,
      fals_norm_fallback = isTRUE(led$fallback_norm)),
    refined_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  if (isTRUE(verbose)) {
    cat(sprintf("[refine] %s %s → %s%s\n", cand$id, cand$mode, verdict,
                if (length(failing)) sprintf(" (%s)", paste(failing, collapse = ",")) else ""))
    cat(sprintf("         %s\n", substr(stmt, 1, 240)))
  }
  res
}

# 활성 목록/미리보기 대상 = active/modes/** 전건 (status 무관 — HELD 도 보여야 한다)
.rs_all_axiom_files <- function(root) {
  d <- file.path(root, "qepm", "memory", "axioms", "active", "modes")
  if (!dir.exists(d)) return(character(0))
  list.files(d, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)
}

# --preview --all : 쓰기 0. ★"전부 HELD"는 "게이트 로직이 죽었다"와 겉보기가 같으므로
#   개별 판정이 아니라 **분포**를 출력한다(실패 사유 히스토그램 포함).
refine_preview_all <- function(root = NULL, files = NULL) {
  root <- root %||% .rs_root()
  fs <- files %||% .rs_all_axiom_files(root)
  if (!length(fs)) { cat("[refine] 대상 공리 0건 (active/modes/**)\n"); return(invisible(list())) }
  corpus <- .rs_load_corpus(root)
  fnorm <- .rs_resolve_fals_norm(NULL, root)
  docs <- lapply(fs, function(f) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  names(docs) <- fs
  docs <- Filter(Negate(is.null), docs)
  out <- list(); hist <- list()
  cat(sprintf("%-13s %-16s %-11s %-8s %s\n", "AXIOM", "MODE", "POLARITY", "VERDICT", "FAILING / inject"))
  cat(strrep("-", 118), "\n", sep = "")
  for (f in names(docs)) {
    d <- docs[[f]]
    self_id <- as.character(d$axiom_id %||% "")[1]
    peers <- Filter(function(p) !identical(as.character(p$axiom_id %||% "")[1], self_id) &&
                      (as.character(p$status %||% "active")[1] %in% c("active", "proposed")), docs)
    r <- tryCatch(refine_statement(d, corpus = corpus, fals_norm = fnorm, peers = peers, root = root),
                  error = function(e) list(axiom_id = self_id, verdict = "ERROR",
                                           failing = list(conditionMessage(e)),
                                           statement_inject = "", gates = list()))
    out[[self_id]] <- r
    for (k in unlist(r$failing)) hist[[k]] <- (hist[[k]] %||% 0L) + 1L
    cat(sprintf("%-13s %-16s %-11s %-8s %s\n", r$axiom_id,
                as.character(d$research_mode %||% "?")[1],
                as.character(d$polarity %||% "?")[1], r$verdict,
                if (length(r$failing)) paste(gsub("_.*$", "", unlist(r$failing)), collapse = ",")
                else substr(r$statement_inject, 1, 62)))
  }
  vd <- table(vapply(out, function(z) z$verdict, character(1)))
  cat(strrep("-", 118), "\n", sep = "")
  cat(sprintf("[refine] %d\uac74 \u2014 %s\n", length(out),
              paste(sprintf("%s=%d", names(vd), as.integer(vd)), collapse = " ")))
  if (length(hist)) {
    hk <- names(hist)[order(-unlist(hist))]
    cat(sprintf("[refine] \uc2e4\ud328 \uc0ac\uc720 \ubd84\ud3ec: %s\n",
                paste(sprintf("%s=%d", hk, unlist(hist[hk])), collapse = " ")))
  }
  cat("[refine] \u2605 \uc804\ubd80 HELD \ub610\ub294 \uc804\ubd80 REFINED \ub294 \uac8c\uc774\ud2b8 \uc0ac\ub9dd\uacfc \uacb0\uacfc\uac00 \uac19\ub2e4 \u2014 \ubd84\ud3ec\ub97c \ubcfc \uac83.\n")
  invisible(out)
}

# --backfill : 기존 active/modes/** 공리에 refine_* 필드를 적재한다(문장은 덮어쓰지 않는다).
#   ★status 는 건드리지 않는다 — 활성화는 promote.R(커밋16)의 소관이다.
refine_backfill <- function(root = NULL, apply = TRUE) {
  root <- root %||% .rs_root()
  fs <- .rs_all_axiom_files(root)
  corpus <- .rs_load_corpus(root)
  fnorm <- .rs_resolve_fals_norm(NULL, root)
  n_w <- 0L
  for (f in fs) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    r <- tryCatch(refine_statement(d, corpus = corpus, fals_norm = fnorm, root = root),
                  error = function(e) NULL)
    if (is.null(r)) next
    same <- identical(as.character(d$refine_verdict %||% ""), r$verdict) &&
      identical(as.character(d$refine_input_sha %||% ""), r$refine_input_sha)
    if (same) { cat(sprintf("[refine][backfill] %s 무변경(sha 동일)\n", r$axiom_id)); next }
    d$refine_verdict <- r$verdict
    d$refine_failing <- r$failing
    d$refine_gates <- lapply(r$gates, function(g) g$pass)
    d$refine_input_sha <- r$refine_input_sha
    d$refine_attempts <- as.integer(d$refine_attempts %||% 0L) + 1L
    d$refined_at <- r$refined_at
    d$statement_inject <- r$statement_inject
    d$needs_refinement <- !identical(r$verdict, "REFINED")
    if (identical(r$verdict, "REFINED")) {
      d$statement <- r$statement; d$canonical_statement <- r$statement; d$text <- r$statement
    }
    if (isTRUE(apply)) {
      write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null"); n_w <- n_w + 1L
      cat(sprintf("[refine][backfill] %s → %s (기록)\n", r$axiom_id, r$verdict))
    } else {
      cat(sprintf("[refine][backfill][dry-run] %s → %s (미기록)\n", r$axiom_id, r$verdict))
    }
  }
  cat(sprintf("[refine][backfill] %d건 기록%s\n", n_w, if (isTRUE(apply)) "" else " (dry-run — 0)"))
  invisible(n_w)
}

if (!interactive() && Sys.getenv("REFINE_SOURCED") != "1" &&
    length(commandArgs(trailingOnly = TRUE)) > 0) {
  .a <- commandArgs(trailingOnly = TRUE)
  .root <- .rs_root()
  if (any(.a == "--backfill")) {
    refine_backfill(root = .root, apply = !any(.a %in% c("--dry-run", "--dryrun")))
  } else if (any(.a == "--all")) {
    refine_preview_all(root = .root)
  } else {
    .p <- .a[!startsWith(.a, "--")]
    if (length(.p)) {
      .r <- refine_statement(.p[1], root = .root, verbose = TRUE)
      cat(sprintf("[refine] verdict=%s sha=%s\n", .r$verdict, substr(.r$refine_input_sha, 1, 12)))
      for (g in names(.r$gates))
        cat(sprintf("   %-17s %-5s %s\n", g, .r$gates[[g]]$pass, .r$gates[[g]]$detail))
      cat(sprintf("   inject: %s\n", .r$statement_inject))
    } else {
      cat("[refine] usage: refine_statement.R [--preview --all | --backfill [--dry-run] | <path>]\n")
    }
  }
}
