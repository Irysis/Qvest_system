# weight_method_gate.R — 판별형 게이트: "이 비중방법이 실제로 EW 가 아닌가"
#
# 왜 이 파일이 있나 (2026-08-24, 도훈 결정 5-b):
#   advanced_weights.R::.normalize 의 순서 결함으로 lean 빌트인 6종이 **정확히 EW** 를
#   내고 있었다. 그런데 그 사실은 이미 06_Registry/weight_catalog.json 의
#   `probe.max_abs_dev_from_ew` 에 **측정돼 커밋돼 있었다**(당시 22개 항목이 정확히 0).
#   아무도 그 값에 걸려 있지 않았을 뿐이다. ⇒ **계기가 없어서가 아니라 게이트가 없어서**
#   지나갔다. 이 파일이 그 게이트다.
#
# ★왜 제약형 게이트로는 못 잡나:
#   등록된 worktask_constraint_enforcer.sh 는 종목수·bounds·Σw 를 강제하는데, EW 는
#   그 셋을 **전부** 만족한다 — 실현가능집합에서 가장 준수적인 점이다. 제약형 게이트는
#   EW 붕괴를 영원히 통과시킨다([[reference-no-signal-control-gate]] 와 같은 형태:
#   제약형 롱온리는 '벤치를 이겼다'로 신호 기여를 증명하지 못한다).
#   ⇒ 게이트는 **판별형**이어야 한다: 산출이 EW 와 구분되는가를 직접 본다.
#
# 계약 (3상태 — 미측정은 위반이 아니다):
#   PASS      probe$max_abs_dev_from_ew >  0  → 신호가 살아 있다
#   VIOLATION probe$max_abs_dev_from_ew == 0  → **이름만 다른 EW**. 원인(순서 결함이든
#             wrapper 폴백이든) 무관하게 막는다 — 결과가 같기 때문이다.
#   UNKNOWN   카탈로그에 없거나 probe 미측정 → **차단하지 않고 보고만** 한다.
#             미측정을 위반으로 계상하면 "빈 결과 = 불합격"이 되어 정반대 방향으로
#             같은 실수를 한다.
#
# 재생성: source('02_Infrastructure/portfolio/weight_catalog.R'); sync_catalog()
# 검사기: 08_Tests/contracts/test_weight_method_gate.R (양성/위반주입/돌연변이)

# ★정의를 사용보다 **앞에** 둔다 — 이 저장소에서 같은 형태의 사용-전-정의가
#   test_no_signal_control.R:5 에 있었고, base R 이 %||% 를 제공하지 않았다면
#   그 줄에서 죽었다(실제로는 sys.frame 쪽이 먼저 죽었다).
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

.wmg_root <- function(root = NULL) {
  if (!is.null(root) && nzchar(root)) return(gsub("\\\\", "/", root))
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  for (c in cand) {
    if (!nzchar(c)) next
    c <- gsub("\\\\", "/", c)
    if (dir.exists(file.path(c, "06_Registry")) &&
        dir.exists(file.path(c, "02_Infrastructure"))) return(c)
  }
  gsub("\\\\", "/", getwd())
}

.wmg_norm <- function(x) tolower(gsub("[^a-z0-9]", "", tolower(as.character(x))))

#' 카탈로그에서 비중방법을 찾아 probe 판정을 돌려준다.
#' @return list(verdict = PASS|VIOLATION|UNKNOWN, catalog_id, dev, reason, log)
weight_method_probe_verdict <- function(method, root = NULL) {
  out <- list(verdict = "UNKNOWN", catalog_id = NA_character_,
              dev = NA_real_, reason = NA_character_, log = NA_character_,
              detail = "카탈로그 미조회")
  if (is.null(method) || !length(method) || !nzchar(as.character(method)[1]))
    return(out)
  m <- as.character(method)[1]
  p <- file.path(.wmg_root(root), "06_Registry", "weight_catalog.json")
  if (!file.exists(p)) { out$detail <- paste("카탈로그 부재:", p); return(out) }
  d <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(d) || is.null(d$entries)) { out$detail <- "카탈로그 파싱 실패"; return(out) }

  key <- .wmg_norm(m)
  # ★해석 순서가 계약이다 — 접두 없는 이름은 여러 계열에 걸린다(예: "MaxDiv" 는
  #   lean:maxdiv 와 qepm:MaxDiv 둘 다). 첫 일치를 **조용히** 고르면 퇴화한 쪽을
  #   그냥 놓친다. ⇒ ①catalog_id 정확 일치가 이긴다 ②아니면 후보를 전부 모아
  #   1건일 때만 판정하고, 2건 이상이면 **모호(UNKNOWN)** 로 보고한다.
  #   모호를 차단으로 처리하지 않는 이유: 정상 이름까지 막는 오탐이 되고, 그러면
  #   게이트가 우회당한다(이 저장소가 검사기에 대해 겪은 경로 그대로다).
  exact <- NULL; cands <- list()
  for (e in d$entries) {
    cid <- as.character(e$catalog_id %||% "")
    if (.wmg_norm(cid) == key) { exact <- e; break }
    alias <- c(e$label, sub("^[a-z]+:", "", cid))
    if (key %in% vapply(alias, .wmg_norm, character(1)))
      cands[[length(cands) + 1L]] <- e
  }
  hit <- if (!is.null(exact)) exact else if (length(cands) == 1L) cands[[1]] else NULL
  if (is.null(hit) && length(cands) > 1L) {
    lab <- vapply(cands, function(e) {
      pr <- e$probe
      dv <- if (is.null(pr) || is.null(pr$max_abs_dev_from_ew)) NA_real_ else
              suppressWarnings(as.numeric(pr$max_abs_dev_from_ew))
      sprintf("%s(dev=%s)", as.character(e$catalog_id),
              if (is.na(dv)) "미측정" else format(dv, digits = 4))
    }, character(1))
    out$detail <- sprintf("모호 — '%s' 가 %d건에 걸린다: %s. 접두를 붙여 지정할 것",
                          m, length(cands), paste(lab, collapse = " · "))
    return(out)
  }
  if (is.null(hit)) { out$detail <- sprintf("'%s' 가 카탈로그에 없다", m); return(out) }

  out$catalog_id <- as.character(hit$catalog_id)
  pr <- hit$probe
  if (is.null(pr) || is.null(pr$max_abs_dev_from_ew)) {
    out$detail <- "probe 미측정 — 판정 없음(차단 아님)"; return(out)
  }
  out$dev    <- suppressWarnings(as.numeric(pr$max_abs_dev_from_ew))
  out$reason <- if (is.null(pr$reason)) NA_character_ else as.character(pr$reason)
  out$log    <- if (is.null(pr$log))    NA_character_ else as.character(pr$log)
  if (is.na(out$dev)) { out$detail <- "probe dev 값이 NA — 판정 없음"; return(out) }
  out$verdict <- if (out$dev > 0) "PASS" else "VIOLATION"
  out$detail  <- sprintf("max_abs_dev_from_ew = %.8g", out$dev)
  out
}

#' 소비 직전 호출. VIOLATION 이면 기본적으로 중단한다.
#' @param strict TRUE = stop / FALSE = warning (경보 표면용)
assert_weight_method_alive <- function(method, root = NULL, strict = TRUE) {
  v <- weight_method_probe_verdict(method, root)
  if (identical(v$verdict, "VIOLATION")) {
    msg <- paste0(
      sprintf("[weight-gate] '%s' 는 카탈로그 probe 상 **정확히 EW** 다", method),
      sprintf(" (max_abs_dev_from_ew = 0, id = %s).\n", v$catalog_id),
      sprintf("  사유: %s\n", if (is.na(v$reason)) "(미기재)" else v$reason),
      sprintf("  → 이 방법으로 낸 성과는 EW 성과이지 '%s' 성과가 아니다.", method),
      " 어댑터를 고치거나 다른 방법을 쓸 것.\n",
      "  재측정: source('02_Infrastructure/portfolio/weight_catalog.R'); sync_catalog()")
    if (isTRUE(strict)) stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
  }
  invisible(v)
}
