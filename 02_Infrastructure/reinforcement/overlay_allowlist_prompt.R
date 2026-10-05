#!/usr/bin/env Rscript
#==============================================================================
# overlay_allowlist_prompt.R — 오버레이 arm 생성 프롬프트의 '허용 함수 목록' 렌더러
#   (도훈 결정 B09-ALLOWLIST-PROMPT 2026-09-25 19시 · 06_Registry/decision_register.json)
#
# ★왜: R3R(P0-09 정적 probe 경화 ③d) 이후 probe 는 정본 arm 이 쓰는 이름 전수(06_Registry/overlay_probe_allowlist.json · 동결)
#   밖의 이름을 **전부** 거부한다. 생성 레인(rf_overlay_propose.sh · rf_b5_design.sh)의 프롬프트가 그 목록을 모르면 LLM 은
#   흔한 함수 하나(목록 밖)로 arm 을 버린다 — R3R 빌드 노트: 공통 arm 하나 빼고 만든 목록으로 그 arm 을 재면 17/23 통과
#   ("새 arm 약 1/4 은 목록 밖 함수 1~4개로 거부될 수 있다 — 생성 프롬프트에 목록 제시 권고").
# ★읽는 코드는 한 벌: 목록은 probe 자신의 적재기 overlay_probe_allowlist_params(root) 로 읽는다
#   (common ∪ widened · 스키마 · 능력 계열 오염 검사 · root → QM_ROOT 폴백까지 probe 와 같다). 프롬프트가 보여주는 집합 =
#   probe 가 실제로 대조하는 집합. 이 파일에 JSON 사본 파서를 두지 않는다(두 벌이면 한쪽만 낡는다).
# ★하드코딩 없음: 이름·키·참조 이름공간·개별 허가는 전부 레지스트리에서, 함수 자리 인자 이름·연산자 문자열은 probe 상수
#   (.OP_FN_FORMALS · .OP_FN_SYNTAX_STR)에서 온다. 이 파일이 아는 것은 키의 뜻풀이(표시 문구)뿐 — 모르는 키도 그대로 싣는다.
# 부재 거동(설계 선택 — 소비자가 고른다):
#   적재기 부재(R3R 미배포)·레지스트리 부재·손상·스키마 불일치·능력 계열 오염·참조 이름공간 미설치 = ok=FALSE + 사유 + '미제공' 블록.
#   (참조 이름공간 미설치 = 적대 검증 수리 2026-09-25 — probe 가 판정 불가로 전부 거부하는 상태를 렌더가 ok 로 내던 구멍)
#   이때 probe 도 모든 새 arm 을 거부한다(③d fail-closed — 미측정은 통과가 아니다).
#   · 생성 전용 레인 rf_overlay_propose.sh = LLM 을 부르지 않고 멈춘다(산출물이 반드시 거부될 호출 — 한도·방출 몫만 태운다).
#   · B5 설계 레인 = '목록 미제공 · 새 arm 을 내지 마라' 를 재료 (7)·(8) 에 명시하고 배합(스택) 설계는 계속한다(배합은 목록과 무관).
# 사용:
#   source/sys.source → overlay_allowlist_prompt(root, probe_path) → list(ok, reason, lines, path, sha256, n_names, fallback)
#   Rscript overlay_allowlist_prompt.R <out.txt> [root] [probe_path]
#     → rc 0 = 목록 렌더(out 에 씀) · rc 3 = 미제공(out 에 미제공 블록) · rc 2 = 인자 오류
#       마지막 줄 "allowlist: ok | <이름 수> | sha <앞 12>" 또는 "allowlist: unavailable | <사유>"
#   root 기본 = QVEST_RF_ROOT > QM_ROOT · probe_path 기본 = 이 파일 옆 overlay_probe.R(CLI) / root 아래(함수)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

OAP_REG_REL   <- "06_Registry/overlay_probe_allowlist.json"          # 표시용 — 실제 찾기·읽기는 probe 적재기
OAP_PROBE_REL <- "02_Infrastructure/reinforcement/overlay_probe.R"
#' 키 뜻풀이(표시 문구) — 판정 규칙의 정본은 overlay_probe.R ③d(R1~R7). 여기 없는 키도 이름 그대로 싣는다(목록 누락 0).
OAP_KEY_DESC <- c(
  calls     = "호출할 수 있는 함수·연산자",
  values    = "값 자리(호출하지 않고 이름으로)에 쓸 수 있는 참조 이름",
  shadow    = "지역 변수로 대입해 가려도 되는 참조 이름(이 파일이 대입했을 때만)",
  strings   = "문자열로 적어도 되는 고차 함수·능력 계열 이름",
  fnargs    = "고차 함수의 함수 자리 인자%s로 넘길 수 있는 함수 이름(그 자신이 고차 함수가 아닐 것)",
  fnstrs    = "함수 자리 인자에 문자열로 넘길 수 있는 이름",
  headcalls = "계산된 호출 머리 f(…)(…) 의 f 로 허용",
  pkgs      = "pkg::name 접두로 쓸 수 있는 패키지(name 은 위 목록 안이어야 한다 · ::: 금지)")

.oap_bq  <- function(x) if (length(x)) paste(sprintf("`%s`", x), collapse = ", ") else "(없음)"
.oap_srt <- function(x) { x <- unique(as.character(x)); x <- x[!is.na(x) & nzchar(x)]; sort(x, method = "radix") }
.oap_one <- function(x) substr(gsub("[\r\n]+", " ", paste(as.character(x), collapse = " ")), 1L, 240L)

.oap_unavailable_lines <- function(why) c(
  sprintf("### 허용 함수 목록 — 미제공 (%s)", why),
  sprintf("- ★probe ③d 는 허용 목록(%s)을 적재하지 못하면 **모든 새 arm 을 거부한다**(fail-closed · 미측정은 통과가 아니다).", OAP_REG_REL),
  "- 그래서 이번에는 새 arm 을 내지 마라 — 내도 probe 에서 거부·삭제되고 방출 원장에 거부로 남는다.")

#' @param root       데이터 루트 — probe 가 레지스트리를 찾는 자리(overlay_probe_arm(kind, root) 와 같은 값을 넘겨라)
#' @param probe_path 적재기를 빌릴 overlay_probe.R — 소비 레인의 probe 와 같은 파일
overlay_allowlist_prompt <- function(root = Sys.getenv("QVEST_RF_ROOT", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                                     probe_path = file.path(root, OAP_PROBE_REL)) {
  root <- sub("/+$", "", gsub("\\", "/", root, fixed = TRUE))
  un <- function(why) { why <- .oap_one(why)
    list(ok = FALSE, reason = why, lines = .oap_unavailable_lines(why), path = NA_character_, sha256 = "", n_names = 0L, fallback = FALSE) }
  if (!file.exists(probe_path)) return(un(sprintf("probe 부재 — %s", probe_path)))
  en <- new.env(parent = globalenv())
  e1 <- tryCatch({ invisible(capture.output(suppressMessages(sys.source(probe_path, envir = en)))); NULL },
                 error = function(e) conditionMessage(e))
  if (!is.null(e1)) return(un(sprintf("probe 적재 실패 — %s", e1)))
  if (!is.function(en$overlay_probe_allowlist_params))
    return(un("probe 에 허용 목록 적재기(overlay_probe_allowlist_params)가 없다 — ③d 미배포(R3R 이전 판)"))
  al <- tryCatch(en$overlay_probe_allowlist_params(root), error = function(e) list(ok = FALSE, reason = conditionMessage(e)))
  if (!isTRUE(al$ok)) return(un(al$reason %||% "적재기가 사유 없이 거부"))
  cm <- al$common
  if (!is.list(cm) || !length(cm) || is.null(names(cm))) return(un("적재기 반환에 common 목록이 없다"))
  # (적대 검증 수리 2026-09-25) 열 이름 면제는 probe R2 그대로 — 픽스처 열은 **참조 이름공간에 없을 때만** 맨이름 값으로 면제된다.
  #   참조 이름과 겹치는 열(hold 의 하방베타 열처럼 base·stats 함수 이름과 같은 열)을 data.table 안 맨이름으로 쓰면 value_not_allowed.
  #   겹침 = probe 자신의 참조 색인(.op_ref_index) × (픽스처 열 overlay_probe_fixture ∪ schema_columns) − values — 사본·하드코딩 없음.
  #   참조 이름공간이 하나라도 미설치면 probe 는 모든 arm 을 판정 불가로 거부한다(fail-closed) → 여기서도 미제공(렌더 ok ⇔ probe 판정 가능).
  ref <- tryCatch(en$.op_ref_index(al$ref_ns %||% character(0)), error = function(e) NULL)
  if (!is.list(ref)) return(un("probe 참조 이름공간 색인 실패(.op_ref_index)"))
  if (length(ref$missing)) return(un(sprintf("참조 이름공간 미설치 %s — probe 가 모든 arm 을 판정 불가로 거부한다", paste(ref$missing, collapse = ","))))
  fxc <- tryCatch(en$overlay_probe_fixture(), error = function(e) NULL)
  coll <- .oap_srt(setdiff(intersect(.oap_srt(c(names(fxc$M), names(fxc$hold), al$schema_cols)), ref$all), cm$values))
  sha <- tryCatch(as.character(en$.op_sha256(al$path)), error = function(e) "")
  fnf <- if (is.character(en$.OP_FN_FORMALS)) sprintf("(%s)", paste(en$.OP_FN_FORMALS, collapse = "·")) else ""
  syn <- if (is.character(en$.OP_FN_SYNTAX_STR)) sprintf(" · 그 밖에 문법 연산자 문자열 %s 도 허용", .oap_bq(en$.OP_FN_SYNTAX_STR)) else ""
  L <- c(sprintf("### 허용 함수 목록 — probe ③d 정적 대조 (정본 %s · 동결 · 목록 밖 = 등재 거부)", OAP_REG_REL),
         "- probe 는 arm 소스의 모든 이름을 파서로 뽑아 아래 목록과 대조한다. 목록 밖 이름이 **하나라도** 있으면 probe FAIL → 등재 거부(arm 파일 삭제 · 방출 원장에 거부 기록).",
         "  흔한 함수라도 여기 없으면 거부된다 — 목록 안 함수의 조합으로 써라. 목록은 동결이다(새 arm 이 자기 허가를 만들 수 없다 · 넓히기 = 사람 검토).",
         "- 목록과 무관하게 쓸 수 있는 것: 이 파일 안에서 대입한 지역 변수·도우미 함수(참조 이름공간에 없는 이름) · H·ctx$hold 의 열($ 로 읽을 때 — data.table 안 맨이름은 그 열 이름이 참조 이름공간에 없을 때만) · 함수 리터럴 function(x) … .",
         sprintf("- 참조 이름공간(이 안의 이름은 아래 목록에 있어야 쓸 수 있다): %s", .oap_bq(al$ref_ns %||% character(0))))
  if (length(coll)) L <- c(L, sprintf("  ★열 이름이 참조 이름공간의 이름과 겹치면 data.table 안 맨이름(값 자리)은 목록 밖 참조로 잡혀 거부된다 — $ 로 읽어라(H$열 · ctx$hold$열). 겹치는 열: %s", .oap_bq(coll)))
  if (isTRUE(al$fallback)) L <- c(L, sprintf("- (데이터 루트에 목록이 없어 QM_ROOT 판을 읽었다 — probe 도 같은 판으로 잰다: %s)", al$path))
  n_tot <- 0L
  for (k in names(cm)) {
    v <- .oap_srt(cm[[k]]); n_tot <- n_tot + length(v)
    d <- if (k %in% names(OAP_KEY_DESC)) OAP_KEY_DESC[[k]] else "레지스트리 키(뜻풀이 없음 — 판정은 probe)"
    if (k == "fnargs") d <- sprintf(d, fnf)
    tail_k <- if (k == "fnstrs") paste0(syn, " · do.call 에는 문자열 전면 금지") else ""
    L <- c(L, sprintf("- %s — %s (%d종): %s%s", k, d, length(v), .oap_bq(v), tail_k))
  }
  gr <- al$grants %||% list()
  if (length(gr)) {
    L <- c(L, sprintf("- 개별 허가 %d건 — **새 arm 에는 적용되지 않는다**(각 정본 파일의 sha256 에만 묶인 예외 · 한 바이트라도 다르면 공통 목록으로만 잰다). 그 파일을 본보기로 베껴 아래 이름을 쓰면 probe 가 거부한다:", length(gr)))
    for (g in names(gr)) {
      nm <- .oap_srt(unlist(gr[[g]][setdiff(names(gr[[g]]), "sha256")], use.names = FALSE))
      L <- c(L, sprintf("  · %s — 그 파일만 쓰는 이름 %d종: %s", g, length(nm), .oap_bq(nm)))
    }
  }
  list(ok = TRUE, reason = NA_character_, lines = L, path = al$path, sha256 = sha, n_names = n_tot, fallback = isTRUE(al$fallback))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
if (!interactive() && identical(sys.nframe(), 0L)) {
  a <- commandArgs(TRUE)
  if (!length(a) || !nzchar(a[1])) { cat("usage: Rscript overlay_allowlist_prompt.R <out.txt> [root] [probe_path]\n"); quit(status = 2L) }
  self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1] %||% "")
  root <- if (length(a) >= 2L && nzchar(a[2])) a[2] else Sys.getenv("QVEST_RF_ROOT", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
  pp <- if (length(a) >= 3L && nzchar(a[3])) a[3] else
    if (!is.na(self) && nzchar(self)) file.path(dirname(gsub("\\", "/", self, fixed = TRUE)), "overlay_probe.R") else file.path(root, OAP_PROBE_REL)
  r <- overlay_allowlist_prompt(root, pp)
  dir.create(dirname(a[1]), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(r$lines), a[1], useBytes = TRUE)
  if (isTRUE(r$ok)) cat(sprintf("allowlist: ok | %d | sha %s\n", r$n_names, substr(r$sha256, 1L, 12L))) else
    cat(sprintf("allowlist: unavailable | %s\n", r$reason))
  quit(status = if (isTRUE(r$ok)) 0L else 3L)
}
