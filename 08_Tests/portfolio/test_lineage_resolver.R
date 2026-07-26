#==============================================================================
# test_lineage_resolver.R — measurement_basis_audit.R v1.12 계보 resolver 회귀 가드
#
# 배경: v1.10/v1.11 은 STR_1715 오버레이 부품이 교체될 때마다(.SLEEVE_ALIASES 에)
#   별칭을 손으로 추가해야 했다. 원인은 find_latest_wt/find_lineage_wts 의
#   str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$","", str_id) 절단 — 첫 "_M" 에서
#   잘려 "STR_1715_on" 이 되고 terminal ga str_id 와 substring 불일치 → NO_WT(DRIFTED).
#   v1.12 가 .lineage_anchor(선두 STR_<digits>) + .lineage_related(토큰 경계)로 교체하며
#   STR_1715 계열 하드코딩 별칭 4종을 제거했다.
#
# ★이 테스트가 존재하는 이유: v1.12 주석이 "test_resolver.R 실측 16-id" 를 인용하지만
#   그 파일은 저장소에 없었다(2026-07-26 좌초 수리 회수 시 확인). 인용된 검증이
#   재실행 불가능하면 없는 것과 같으므로 여기에 정본으로 다시 세운다.
#
# ★위반 주입 테스트 필수: 앵커 매칭이 너무 넓어지면(STR_1715 가 STR_17150 / EQUITY_1715 에
#   붙으면) 오매칭이 조용히 잘못된 WT 의 cert 를 빌려온다. "통과"만 세는 테스트는
#   검사가 죽어도 똑같이 초록이므로, 반드시 FALSE 여야 하는 축을 함께 잰다.
#
# 위반 주입 실측 (2026-07-26, 돌연변이 4종 교차): 위반 주입 축은 서로 다른 회귀를 겨냥한다.
#   돌연변이            | 잡는 위반 주입 축
#   경계 제거(구 버그)  | STR_17150
#   앵커에서 STR_ 탈락  | STR_17150 · EQUITY_1715
#   앵커 자릿수 절단    | STR_17150 · STR_1716
#   가드 소실(상시TRUE) | STR_17150 · STR_1716 · EQUITY_1715 · TSMOM
#   길이0 후보          | (오매칭 아닌 크래시 축 — 가드 제거 시 length-zero 에러)
#   → 5 위반 주입 축 전부 최소 1개 회귀를 잡는다. 새 위반 주입 축 추가 시 이 표도 갱신할 것.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

#──────────────────────────────────────────────────────────────────────────────
# PROJECT_ROOT 해석 — r-portability.md 금칙 ③④ 정합:
#   존재검사(dir.exists)로 정체를 대신하지 않고 표지 파일로 확인하며,
#   CLAUDE_PROJECT_DIR 를 최우선 후보로 둔다. 전부 실패 시 조용한 폴백 대신 stop().
#──────────────────────────────────────────────────────────────────────────────
.MARKER <- "02_Infrastructure/portfolio/measurement_basis_audit.R"

.is_proj_root <- function(p) {
  nzchar(p) && dir.exists(p) && file.exists(file.path(p, .MARKER))
}

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  dirname(sub("^--file=", "", m[1L]))
}

.sd <- .script_dir()
.CANDIDATES <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
  Sys.getenv("QM_ROOT",            unset = ""),
  if (nzchar(.sd)) file.path(.sd, "..", "..") else "",   # 08_Tests/portfolio → root
  getwd(),
  file.path(getwd(), "..", "..")
)

PROJ_ROOT <- ""
for (.c in .CANDIDATES) {
  if (.is_proj_root(.c)) { PROJ_ROOT <- .c; break }
}
if (!nzchar(PROJ_ROOT)) {
  stop(sprintf(paste0(
    "[test_lineage_resolver] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보가 없음.\n",
    "  시도한 후보: %s\n  cwd=%s"),
    .MARKER,
    paste(sprintf("'%s'", .CANDIDATES[nzchar(.CANDIDATES)]), collapse = ", "),
    getwd()))
}

# CLI entrypoint 는 commandArgs(trailingOnly=TRUE) 비어 있으면 발화하지 않는다 → source 안전.
source(file.path(PROJ_ROOT, .MARKER))

PASS <- 0; FAIL <- 0; results <- character()

check <- function(name, expect, actual) {
  if (identical(expect, actual)) {
    PASS <<- PASS + 1
    results <<- c(results, sprintf("  PASS  %s", name))
  } else {
    FAIL <<- FAIL + 1
    results <<- c(results, sprintf("  FAIL  %s  (expect=%s actual=%s)",
                                   name, format(expect), format(actual)))
  }
}

# legacy_root = v1.11 이전 절단 root. STR-family 에선 무시되고 비-STR fallback 에만 쓰인다.
.legacy_root <- function(id) sub("(_WT|_Iter|_M|_S|_v).*$", "", id)

rel <- function(str_id, candidate) {
  .lineage_related(str_id, candidate, .legacy_root(str_id))
}

#──────────────────────────────────────────────────────────────────────────────
# A. .lineage_anchor — STR-family 만 앵커를 갖는다
#──────────────────────────────────────────────────────────────────────────────
check("anchor: 현 book id",
      "STR_1715", .lineage_anchor("STR_1715_on_M4gAE_R05_noLayer4_PG2"))
check("anchor: v1.8 별칭 원본",
      "STR_1715", .lineage_anchor("STR_1715_AR_threshold_overlay_PG2_v2_alpha_2026_04"))
check("anchor: terminal ga str_id",
      "STR_1715", .lineage_anchor("STR_1715_AR_on_M4_R05_overlay_PG2"))
check("anchor: 비-STR(TSMOM) = NA",
      NA_character_, .lineage_anchor("TSMOM_8_ETF_rotation_PG2_no_KR_bond_overlap"))
check("anchor: CASH = NA",  NA_character_, .lineage_anchor("CASH_KRW"))
check("anchor: COMPOSITE = NA",
      NA_character_, .lineage_anchor("COMPOSITE_KR_EQUITY_1715_NEW_SLEEVE"))

#──────────────────────────────────────────────────────────────────────────────
# B. 양성 — 제거된 하드코딩 별칭 4종이 앵커로 자동 resolve 되는가
#    (이게 FALSE 면 v1.10/v1.11 처럼 손수 별칭 추가로 되돌아간다)
#──────────────────────────────────────────────────────────────────────────────
TERMINAL <- "STR_1715_AR_on_M4_R05_overlay_PG2"
check("removed alias v1.8",
      TRUE, rel("STR_1715_AR_threshold_overlay_PG2_v2_alpha_2026_04",
                "STR_1715_AR_threshold_overlay_PG2"))
check("removed alias v1.9",  TRUE, rel("STR_1715_AR_on_M4_PG2",
                                       "STR_1715_AR_threshold_overlay_PG2"))
check("removed alias v1.10", TRUE, rel("STR_1715_on_M4_R05_noLayer4_PG2", TERMINAL))
check("removed alias v1.11", TRUE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", TERMINAL))
# 미래의 부품 교체(아직 존재하지 않는 접미)도 별칭 없이 잡혀야 한다 — 근절의 핵심 주장.
check("미래 오버레이 접미(별칭 부재)",
      TRUE, rel("STR_1715_on_M9gXX_R07_FaithTrend_PG2", TERMINAL))
# discovery_of blob 처럼 앞에 다른 토큰이 붙은 후보
check("lineage blob 내 앵커", TRUE,
      rel("STR_1715_on_M4gAE_R05_noLayer4_PG2",
          "WT-D20260430_001 STR_1715_AR_on_M4_R05_overlay_PG2"))

#──────────────────────────────────────────────────────────────────────────────
# C. ★위반 주입 테스트 — 반드시 FALSE. 하나라도 TRUE 면 앵커가 과대매칭(= 남의 cert 차용)
#──────────────────────────────────────────────────────────────────────────────
check("NEG 숫자경계: STR_1715 !~ STR_17150",
      FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", "STR_17150_other_PG2"))
check("NEG 인접번호: STR_1715 !~ STR_1716",
      FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", "STR_1716_AR_overlay_PG2"))
check("NEG 접미숫자: STR_1715 !~ EQUITY_1715",
      FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2",
                 "COMPOSITE_KR_EQUITY_1715_NEW_SLEEVE"))
check("NEG 빈 후보", FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", ""))
# character(0) 은 오매칭이 아니라 크래시 축이다: 가드를 빼면 grepl 이 logical(0) 을
# 돌려주고 if() 가 "argument is of length zero" 로 죽는다(2026-07-26 실측).
check("NEG 길이0 후보(크래시 가드)",
      FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", character(0)))
check("NEG 무관 sleeve",
      FALSE, rel("STR_1715_on_M4gAE_R05_noLayer4_PG2", "TSMOM_ETF_rotation_PG2"))

#──────────────────────────────────────────────────────────────────────────────
# D. 비-STR fallback 보존 — 앵커 도입이 기존 substring 동작을 깨지 않았는가
#──────────────────────────────────────────────────────────────────────────────
check("비-STR full-id substring", TRUE,
      rel("TSMOM_ETF_rotation_PG2", "TSMOM_ETF_rotation_PG2_no_KR_bond_overlap"))
check("비-STR 무관 후보 = FALSE", FALSE,
      rel("TSMOM_ETF_rotation_PG2", "KR_10y_bond_sleeve"))

#──────────────────────────────────────────────────────────────────────────────
# E. 별칭 표 상태 — STR_1715 4종은 제거되고 cross-family rename 만 남아야 한다
#──────────────────────────────────────────────────────────────────────────────
alias_keys <- names(.SLEEVE_ALIASES)
check("별칭표: STR_1715 하드코딩 0건",
      TRUE, !any(grepl("^STR_1715", alias_keys)))
check("별칭표: 비-STR cross-family rename 보존",
      TRUE, "TSMOM_8_ETF_rotation_PG2_no_KR_bond_overlap" %in% alias_keys)

#──────────────────────────────────────────────────────────────────────────────
# F. E2E — 실제 book_state 가 별칭 없이도 HEALTHY 로 resolve 되는가
#    (book_state 부재 시 SKIP: 이 테스트의 A~E 는 book 과 무관하게 유효)
#──────────────────────────────────────────────────────────────────────────────
bs_path <- file.path(PROJ_ROOT, "qepm/mailbox/governor/book_state.json")
wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
if (file.exists(bs_path) && dir.exists(wt_root)) {
  res <- audit_book_measurement_coherence(bs_path, wt_root = wt_root)
  check("E2E: 현 book tier = HEALTHY", "HEALTHY", res$tier)
  check("E2E: NO_WT 잔여 0건", TRUE,
        !any(vapply(res$per_str, function(s) identical(s$tier, "NO_WT"),
                    logical(1))))
} else {
  results <- c(results, "  SKIP  E2E (book_state.json 또는 wt_root 부재)")
}

cat("=== test_lineage_resolver (measurement_basis_audit v1.12) ===\n")
cat(paste(results, collapse = "\n"), "\n")
cat(sprintf("PASS=%d FAIL=%d\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
