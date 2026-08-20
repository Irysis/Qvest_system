# =====================================================================
# test_draft_marker_approval.R — [초안] 마커가 *정제 여부*가 아니라
#   *승인 여부(status)* 로 판정되는지 양방향 검증
# =====================================================================
# 배경(2026-08-20 폐쇄루프 감사 수리대상 ③):
#   구 `.hi_parse_distilled` 는 `statement_refined` 존재 여부로 마커를 결정했다.
#   DIST 카드 lifecycle 은 `pending_5axis → proposed → distilled` 이고 `proposed` 는
#   정제문을 갖지만 **도훈 승인 전**이라, 미승인 카드가 승인 카드와 title 문자열상
#   구분 없이 주입 스트림에 서빙됐다(INV-6 안전속성 누수).
#
# ★검증 규율: 대리 지표를 내용 기반으로 바꾸는 수리는 검출력을 죽이기 쉽다.
#   그래서 [정상]만이 아니라 [위반 주입]을 반드시 함께 돌리고,
#   ★[조작 선행검증] — 픽스처가 *실제로* 의도한 status 를 갖는지 먼저 증명한 뒤에만
#   결론을 낼 자격이 생긴다(치환 실패를 "전파 안 됨"으로 오귀속한 사고 재발 방지).
#
# 실행: cd C:/Users/99922/OneDrive/Quant_Module_Moltbot && Rscript 08_Tests/hooks/test_draft_marker_approval.R
# 원본 06_Registry/distilled_knowledge.json 은 **읽기만** 한다 (픽스처는 메모리 복사본).
# =====================================================================

QM_ROOT_FIX <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = QM_ROOT_FIX)

# ★검사 대상 소스 경로 override 는 **QM_ROOT 로 하면 안 된다**.
#   실측 사고(2026-08-20): `QM_ROOT=<scratch> Rscript ...` 로 구버전을 겨누려 했는데
#   `~/.Renviron` 의 `QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot` 가 셸 상속값을
#   **덮어써서**(R 은 .Renviron 을 시작 시 읽어 덮는다) 신버전이 그대로 소스됐고,
#   그 결과 "구버전에서도 30/30 PASS" 라는 **가짜 검출력 실증**이 나왔다.
#   ⇒ .Renviron 이 건드리지 않는 전용 변수를 쓰고, 아래 PRE-0 이 실제로 무엇을
#     소스했는지 파일 내용으로 증명한다.
SRC <- Sys.getenv("QVEST_HI_SRC",
                  unset = file.path(QM_ROOT_FIX, "02_Infrastructure/tools/hypothesis_index.R"))
DK  <- file.path(QM_ROOT_FIX, "06_Registry/distilled_knowledge.json")

if (!file.exists(SRC)) stop("hypothesis_index.R 부재: ", SRC)
if (!file.exists(DK))  stop("distilled_knowledge.json 부재: ", DK)
SRC_TXT <- readLines(SRC, warn = FALSE)
suppressMessages(suppressWarnings(source(SRC)))

PASS <- 0L; FAIL <- 0L; FAILED <- character(0)
ok <- function(name, cond, detail = "") {
  if (isTRUE(cond)) {
    PASS <<- PASS + 1L; cat(sprintf("  [PASS] %s%s\n", name, if (nzchar(detail)) paste0(" — ", detail) else ""))
  } else {
    FAIL <<- FAIL + 1L; FAILED <<- c(FAILED, name)
    cat(sprintf("  [FAIL] %s%s\n", name, if (nzchar(detail)) paste0(" — ", detail) else ""))
  }
}
# title 에서 dist_id 접두("<ID>: ")를 떼고 남은 앞머리
title_body <- function(t, did) sub(paste0("^", did, ": "), "", t)
has_marker  <- function(t, did, mk) startsWith(title_body(t, did), mk)
# 어떤 종류든 대괄호 마커로 시작하는가 (승인 카드는 FALSE 여야 함)
any_marker  <- function(t, did) grepl("^\\[", title_body(t, did))

cat("=== test_draft_marker_approval.R ===\n")
cat("SRC =", SRC, "\n\n")

# ---------------------------------------------------------------------
# 0) 정본 원본 status 축 전수 나열 (추측 금지 — 실제 값 집합 확인)
# ---------------------------------------------------------------------
cat("[0] 정본 status 축 전수 나열 + 매핑 커버리지\n")
dk <- jsonlite::fromJSON(DK, simplifyVector = FALSE)
stopifnot(!is.null(dk$entries), length(dk$entries) > 0)
sts <- vapply(dk$entries, function(e) as.character(e$status %||% "<MISSING>"), character(1))
tab <- table(sts)
cat("      실측 분포: ", paste(sprintf("%s=%d", names(tab), as.integer(tab)), collapse = " / "), "\n", sep = "")
known <- names(HI_DRAFT_MARKERS)
unknown_sts <- setdiff(names(tab), c(known, "<MISSING>"))
ok("0a 매핑 미등재 status 없음", length(unknown_sts) == 0,
   if (length(unknown_sts)) paste("미등재:", paste(unknown_sts, collapse = ",")) else
     paste("등재", length(known), "종이 정본", length(tab), "종을 전부 덮음"))
ok("0b 승인 status 는 정확히 'distilled' 1종", identical(unname(HI_DRAFT_MARKERS[["distilled"]]), ""),
   "distilled 만 마커 없음")
ok("0c 그 외 4종은 전부 비어있지 않은 마커",
   all(nzchar(unname(HI_DRAFT_MARKERS[setdiff(known, "distilled")]))))

# ---------------------------------------------------------------------
# ★조작 선행검증: 픽스처 빌더가 실제로 의도한 status 를 심는지 먼저 증명
# ---------------------------------------------------------------------
cat("\n[PRE] ★조작 선행검증 — 픽스처가 실제로 의도한 status 를 갖는가\n")
# 승인 카드(distilled) 원본 1건을 템플릿으로 삼아 status 만 바꾼 복사본을 만든다.
tmpl_i <- which(sts == "distilled")[1]
if (is.na(tmpl_i)) stop("정본에 status=distilled 카드가 없어 템플릿을 만들 수 없음")
TMPL <- dk$entries[[tmpl_i]]
stopifnot(nzchar(.hi_join(TMPL$statement_refined)))   # 템플릿은 반드시 정제문 보유
cat("      템플릿 = ", TMPL$dist_id, " (status=", as.character(TMPL$status),
    ", statement_refined 보유=TRUE)\n", sep = "")

mk_fixture <- function(status, dist_id, drop_status = FALSE) {
  e <- TMPL
  e$dist_id <- dist_id
  if (drop_status) e$status <- NULL else e$status <- status
  e
}
FX <- list(
  distilled    = mk_fixture("distilled",            "DIST-FIXT-001"),
  proposed     = mk_fixture("proposed",             "DIST-FIXT-002"),
  quarantined  = mk_fixture("quarantined_evidence", "DIST-FIXT-003"),
  pending      = mk_fixture("pending_5axis",        "DIST-FIXT-004"),
  expired      = mk_fixture("expired",              "DIST-FIXT-005"),
  missing      = mk_fixture(NULL,                   "DIST-FIXT-006", drop_status = TRUE),
  unknown      = mk_fixture("some_future_state",    "DIST-FIXT-007")
)
want <- c(distilled = "distilled", proposed = "proposed",
          quarantined = "quarantined_evidence", pending = "pending_5axis",
          expired = "expired", unknown = "some_future_state")
pre_ok <- TRUE
for (k in names(want)) {
  got <- as.character(FX[[k]]$status %||% "<NULL>")
  if (!identical(got, unname(want[k]))) { pre_ok <- FALSE; cat("      조작 실패:", k, "->", got, "\n") }
}
ok("PRE-1 status 치환이 실제로 먹었다", pre_ok,
   paste(sprintf("%s=%s", names(want), unname(want)), collapse = " / "))
ok("PRE-2 status 결측 픽스처는 실제로 NULL", is.null(FX$missing$status))
ok("PRE-3 전 픽스처가 statement_refined 를 보유(= 구 로직이라면 전부 '마커 없음')",
   all(vapply(FX, function(e) nzchar(.hi_join(e$statement_refined)), logical(1))),
   "이 축이 곧 구/신 로직 판별력 — 정제 여부로는 7건이 구분 불가")
ok("PRE-4 픽스처 id 가 정본과 충돌하지 않음(원본 미수정 보장)",
   length(intersect(vapply(FX, function(e) e$dist_id, character(1)),
                    vapply(dk$entries, function(e) as.character(e$dist_id %||% ""), character(1)))) == 0)
if (!pre_ok) stop("★조작 선행검증 실패 — 이후 결과를 해석할 자격 없음 (오귀속 방지)")

# ---------------------------------------------------------------------
# 1) [정상] 승인 카드(distilled) → 마커 없음
# ---------------------------------------------------------------------
cat("\n[1] [정상] status=distilled → 마커 없음 (경보 오발 없음)\n")
p1 <- .hi_parse_distilled(FX$distilled)
ok("1a distilled 는 어떤 마커도 없음", !any_marker(p1$title, "DIST-FIXT-001"),
   substr(p1$title, 1, 70))
ok("1b distilled_status 행 메타 = distilled", identical(p1$distilled_status, "distilled"))
# 정본 전수 회귀: status=distilled 15건 전부 마커 없이 렌더되는가
d_only <- dk$entries[sts == "distilled"]
n_bad <- sum(vapply(d_only, function(e) {
  p <- .hi_parse_distilled(e); any_marker(p$title, as.character(e$dist_id))
}, logical(1)))
ok("1c 정본 distilled 전수(15건) 오탐 0", n_bad == 0, sprintf("오탐 %d건", n_bad))

# ---------------------------------------------------------------------
# 2) [위반 주입 A] proposed → [미승인 초안]  ★이 수리의 본체
# ---------------------------------------------------------------------
cat("\n[2] [위반 주입 A] status=proposed → '[미승인 초안]' (구 로직은 마커 없이 서빙)\n")
p2 <- .hi_parse_distilled(FX$proposed)
ok("2a proposed 에 [미승인 초안] 마커", has_marker(p2$title, "DIST-FIXT-002", "[미승인 초안]"),
   substr(p2$title, 1, 70))
ok("2b proposed title != distilled title (승인/미승인 구분됨)",
   !identical(title_body(p2$title, "DIST-FIXT-002"), title_body(p1$title, "DIST-FIXT-001")))
# 구 로직 재현(정제 여부 기반) — 같은 픽스처에서 마커가 안 붙는다는 것을 실측으로 보인다.
old_marker <- function(e) {
  refined <- !is.null(e$statement_refined) && nzchar(e$statement_refined %||% "")
  if (refined) "" else "[초안]"
}
ok("2c 구 로직 재현은 proposed 를 '마커 없음'으로 판정(= 이 테스트의 검출력 실증)",
   identical(old_marker(FX$proposed), "") && has_marker(p2$title, "DIST-FIXT-002", "[미승인 초안]"))
# 정본 실카드 전수: proposed 10건이 모두 마커를 받는가
p_only <- dk$entries[sts == "proposed"]
n_marked <- sum(vapply(p_only, function(e) {
  p <- .hi_parse_distilled(e); has_marker(p$title, as.character(e$dist_id), "[미승인 초안]")
}, logical(1)))
ok("2d 정본 proposed 전수 마킹", n_marked == length(p_only),
   sprintf("%d/%d", n_marked, length(p_only)))

# ---------------------------------------------------------------------
# 3) [위반 주입 B] quarantined_evidence → [증거 격리]
# ---------------------------------------------------------------------
cat("\n[3] [위반 주입 B] status=quarantined_evidence → '[증거 격리]'\n")
p3 <- .hi_parse_distilled(FX$quarantined)
ok("3a quarantined 에 [증거 격리] 마커", has_marker(p3$title, "DIST-FIXT-003", "[증거 격리]"),
   substr(p3$title, 1, 70))
q_only <- dk$entries[sts == "quarantined_evidence"]
n_q <- sum(vapply(q_only, function(e) {
  p <- .hi_parse_distilled(e); has_marker(p$title, as.character(e$dist_id), "[증거 격리]")
}, logical(1)))
ok("3b 정본 quarantined 전수 마킹", n_q == length(q_only), sprintf("%d/%d", n_q, length(q_only)))

# ---------------------------------------------------------------------
# 4) [위반 주입 C] expired → [만료], pending_5axis → [초안]
# ---------------------------------------------------------------------
cat("\n[4] [위반 주입 C] expired / pending_5axis 마커\n")
p4 <- .hi_parse_distilled(FX$expired)
ok("4a expired 에 [만료] 마커", has_marker(p4$title, "DIST-FIXT-005", "[만료]"), substr(p4$title, 1, 70))
p5 <- .hi_parse_distilled(FX$pending)
ok("4b pending_5axis 에 [초안] 마커", has_marker(p5$title, "DIST-FIXT-004", "[초안]"), substr(p5$title, 1, 70))
e_only <- dk$entries[sts == "expired"]
n_e <- sum(vapply(e_only, function(e) {
  p <- .hi_parse_distilled(e); has_marker(p$title, as.character(e$dist_id), "[만료]")
}, logical(1)))
ok("4c 정본 expired 전수 마킹(구 로직은 3건이 마커 없이 샜다)", n_e == length(e_only),
   sprintf("%d/%d", n_e, length(e_only)))

# ---------------------------------------------------------------------
# 5) [폴백] status 결측 / 미지 값 → 죽지 않고 보수적 마커
# ---------------------------------------------------------------------
cat("\n[5] [폴백] status 결측 / 미지 값 (회귀 없음 + 보수적 판정)\n")
r_missing <- tryCatch(.hi_parse_distilled(FX$missing), error = function(e) e)
ok("5a status 결측이 예외를 던지지 않음", !inherits(r_missing, "error"),
   if (inherits(r_missing, "error")) conditionMessage(r_missing) else "정상 반환")
if (!inherits(r_missing, "error"))
  ok("5b status 결측 → 보수적 [초안] (승인 취급 금지)",
     has_marker(r_missing$title, "DIST-FIXT-006", "[초안]"), substr(r_missing$title, 1, 70))
r_unknown <- tryCatch(.hi_parse_distilled(FX$unknown), error = function(e) e)
ok("5c 미지 status 가 예외를 던지지 않음", !inherits(r_unknown, "error"))
if (!inherits(r_unknown, "error"))
  ok("5d 미지 status → 보수적 [초안] (조용한 승인 승격 차단)",
     has_marker(r_unknown$title, "DIST-FIXT-007", "[초안]"), substr(r_unknown$title, 1, 70))
# 헬퍼 직접 축 — 배열/NA/빈문자 유입
ok("5e .hi_draft_marker(NULL) = [초안]",   identical(.hi_draft_marker(NULL), "[초안]"))
ok("5f .hi_draft_marker('') = [초안]",     identical(.hi_draft_marker(""), "[초안]"))
ok("5g .hi_draft_marker(NA) = [초안]",     identical(.hi_draft_marker(NA), "[초안]"))
ok("5h .hi_draft_marker(list('proposed')) = [미승인 초안] (배열-안전)",
   identical(.hi_draft_marker(list("proposed")), "[미승인 초안]"))

# ---------------------------------------------------------------------
# 6) 폴백 엔트리(.hi_min_distilled_entry) 도 같은 판정을 쓰는가
# ---------------------------------------------------------------------
cat("\n[6] 파싱실패 폴백 경로도 승인-여부 마커 적용\n")
m2 <- .hi_min_distilled_entry(FX$proposed, "테스트 주입")
ok("6a 폴백 proposed 에 [미승인 초안]", has_marker(m2$title, "DIST-FIXT-002", "[미승인 초안]"),
   substr(m2$title, 1, 70))
m1 <- .hi_min_distilled_entry(FX$distilled, "테스트 주입")
ok("6b 폴백 distilled 는 마커 없음", !any_marker(m1$title, "DIST-FIXT-001"), substr(m1$title, 1, 70))

# ---------------------------------------------------------------------
# 7) 회귀: statement 본문 자체는 손상되지 않았는가 (마커만 추가돼야 함)
# ---------------------------------------------------------------------
cat("\n[7] 회귀 — statement 본문 보존 (마커 접두만 추가)\n")
stmt_of <- function(e) e$statement_refined %||% e$statement_draft %||% ""
n_body_ok <- 0L; n_tot <- 0L
for (e in dk$entries) {
  p  <- .hi_parse_distilled(e)
  did <- as.character(e$dist_id %||% "")
  body <- title_body(p$title, did)
  mk <- .hi_draft_marker(e$status)
  body <- if (nzchar(mk)) sub(paste0("^\\Q", mk, "\\E "), "", body, perl = TRUE) else body
  n_tot <- n_tot + 1L
  if (identical(body, .hi_join(stmt_of(e))) || identical(body, as.character(stmt_of(e)))) n_body_ok <- n_body_ok + 1L
}
ok("7a 정본 전수에서 마커 제거 시 원 statement 와 일치", n_body_ok == n_tot,
   sprintf("%d/%d", n_body_ok, n_tot))

# ---------------------------------------------------------------------
# 8) 실경로 스모크 — lookup_hypothesis 가 마커를 실제로 노출하는가
#    (인덱스가 stale 이면 skip — 재빌드는 이 테스트의 책임이 아님)
# ---------------------------------------------------------------------
cat("\n[8] 실경로 스모크 — lookup_hypothesis (인덱스 있을 때만)\n")
if (file.exists(HI_INDEX_PATH)) {
  pid <- as.character(dk$entries[[ which(sts == "proposed")[1] ]]$dist_id)
  rr <- tryCatch(lookup_hypothesis(tolower(pid), auto_rebuild = FALSE, max_rows = 3),
                 error = function(e) NULL)
  if (!is.null(rr) && nrow(rr) > 0) {
    row <- rr[rr$strategy_id == pid, , drop = FALSE]
    if (nrow(row) > 0) {
      cat("      실경로 title:", substr(row$title[1], 1, 78), "\n")
      cat("      실경로 distilled_status:", row$distilled_status[1], "\n")
      cat("      (인덱스 재빌드 전이면 구 문자열이 남아 있을 수 있음 — 정보용, 채점 제외)\n")
    }
  } else cat("      lookup 0건 또는 실패 — 정보용, 채점 제외\n")
} else cat("      인덱스 파일 부재 — skip\n")

cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) { cat("실패 항목: ", paste(FAILED, collapse = ", "), "\n"); quit(status = 1) }
quit(status = 0)
