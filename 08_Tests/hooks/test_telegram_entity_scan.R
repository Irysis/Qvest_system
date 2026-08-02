#==============================================================================
# test_telegram_entity_scan.R — tg_send_rich() 미지원 HTML entity 스캔 계약 검사기
#
# 계약: .claude/rules/answer-principles.md ("검증 어휘" 정본 = 위반 주입 테스트)
#       + "빈/틀린 결과가 합격으로 읽히지 않을 것"
#
# 배경 (2026-08-02 실측, WT-D20260802_012 R43 발송에서 적발):
#   구 스캔은 TRE(기본 엔진)로 gregexpr("&[a-zA-Z]+;", msg) 했다. Windows R 의 TRE 는
#   위치를 wchar_t = **UTF-16 코드유닛**으로 세는데 regmatches/substr 은 **코드포인트**로
#   자른다 → 매치 앞의 non-BMP 문자(이모지) N개마다 추출 창이 N칸 오른쪽으로 밀린다.
#   tg_agent_brief 는 머리말·섹션마다 이모지를 넣으므로 이 경로 메시지 전부가 해당된다.
#
#   실측: R43 메시지(2412자/4658바이트, non-BMP 6개 = 📡📅📌📖📊🚩)에서
#         '&lt;' 실제 char 위치 1664 · TRE 보고 1670 → 추출 '턱 1.' →
#         정상 escape 된 &lt; 를 "미지원 entity"로 오경보.
#         /tmp/qvest_tg_entity_warn.log 의 07-26~08-02 경보 20건이 전부 이 유령이다.
#
#   ★ 오경보는 시끄러워서 눈에 띄지만, **반대 방향이 본체**다: 창이 밀리면 진짜
#     미지원 entity(&le; 등)는 결코 이름이 불리지 않고, 밀린 창이 우연히 &lt;/&gt;/&amp;
#     위에 떨어지면 setdiff 가 그것을 걸러낸다 — 발화해야 할 바로 그때 조용해진다.
#
# ★이 검사기는 "고친 코드가 통과한다"만 재지 않는다. 같은 픽스처에 **구 로직**을
#   나란히 돌려(C축) 구판이 실제로 틀린 답을 내는지 매 실행 확인한다. 그게 없으면
#   이 검사가 결함을 구별하는지 알 수 없다(픽스처 공허화 방지 — 오탐 제거와 검사
#   사망은 겉보기가 같다).
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             normalizePath(file.path(dirname(sub("^--file=", "",
               grep("^--file=", commandArgs(), value = TRUE)[1])), "..", ".."),
               winslash = "/", mustWork = FALSE),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands) & !is.na(cands)]
  marker <- "02_Infrastructure/telegram/telegram_notify.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

# 검사기가 운영 forensic 원장에 픽스처를 섞지 않도록 격리
Sys.setenv(QVEST_TG_ENTITY_LOG = file.path(tempdir(), "tg_entity_warn_TEST.log"))

suppressMessages(source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R")))
# 네트워크 차단 — tg_send_rich 는 globalenv 에서 tg_send 를 찾는다
assign("tg_send", function(msg, ...) list(ok = TRUE), envir = globalenv())

#──────────────────────────────────────────────────────────────────────────────
# 실제 tg_send_rich 를 돌려 entity 경보만 걷어낸다 (사본 검사 금지 — 원본 함수 경유)
#──────────────────────────────────────────────────────────────────────────────
scan_live <- function(msg) {
  w <- character(0)
  withCallingHandlers(tg_send_rich(msg, validate_emoji = FALSE),
    message = function(m) { w <<- c(w, conditionMessage(m)); invokeRestart("muffleMessage") })
  grep("unsupported HTML entity|색인 붕괴", w, value = TRUE)
}
named <- function(warns) {                      # 경보 문자열에서 지목된 토큰 추출
  if (length(warns) == 0L) return(character(0))
  body <- sub("^.*unsupported HTML entity:\\s*", "", grep("unsupported", warns, value = TRUE))
  # conditionMessage() 는 message() 의 개행을 달고 온다 → 먼저 trim 한 뒤 마침표 제거
  # (TRE 의 '$' 는 끝 개행 앞에서 매치되지 않아, 순서를 바꾸면 '&nbsp;.' 가 남는다)
  body <- sub("\\.\\s*$", "", trimws(body))
  trimws(unlist(strsplit(body, ",")))
}

# ── C축 음성 기준: 수리 전 로직 그대로 (오프셋 계통 결함 포함) ────────────────
scan_legacy <- function(msg) {
  valid_tag <- "b|i|u|s|del|strike|pre|code|a|em|strong|tg-spoiler|tg-emoji|span"
  m <- gsub("&quot;", '"', msg, fixed = TRUE)
  m <- gsub(sprintf("<(?!/?(?:%s)(?:\\s[^>]*)?/?>)", valid_tag), "&lt;", m, perl = TRUE)
  r <- regmatches(m, gregexpr("&[a-zA-Z]+;", m))[[1]]      # ← TRE, 구판 그대로
  setdiff(unique(r), c("&lt;", "&gt;", "&amp;"))
}

EMO <- "\U0001F4E1\U0001F4C5\U0001F4CC\U0001F4D6"   # 📡📅📌📖 — non-BMP 4개 (오프셋 밀림 조건)
ENT_SHAPE <- "^&[A-Za-z][A-Za-z0-9]{0,9};$"

cat("=== telegram entity-scan contract ===\n")

#──────────────────────────────────────────────────────────────────────────────
# A축 — 오경보 금지(정상 메시지는 조용해야 한다)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[A] 정상 메시지 = 무경보\n")

# A1: 실사고 재현 라인 (이모지 뒤 한글 + 정상 escape 되는 '<')
A1 <- paste0(EMO, " R43 상태\n오늘 현행축은 침묵 상태 — 시장 전체 최대 z 0.912 < 문턱 1.0.")
w <- scan_live(A1)
if (length(w) == 0L) {
  ok("A1_no_false_positive", "이모지+한글+'<' → 무경보")
} else {
  bad("A1_no_false_positive", sprintf("오경보 발생: %s", paste(w, collapse = " | ")))
}

# A2: non-BMP 를 크게 늘려도(밀림 폭 확대) 조용해야 한다
A2 <- paste0(strrep("\U0001F4CA\U0001F6A9", 12), " 문턱 <1.0 이고 경계 <2.0 입니다. 판정: DEFER; 이월.")
w <- scan_live(A2)
if (length(w) == 0L) {
  ok("A2_no_false_positive_many_emoji", "non-BMP 24개 → 무경보")
} else {
  bad("A2_no_false_positive_many_emoji", sprintf("오경보: %s", paste(w, collapse = " | ")))
}

# A3: 이모지 없는 순수 한글 (구판도 통과하던 자리 — 회귀 baseline)
A3 <- "시장 전체 최대 z 0.912 < 문턱 1.0 입니다."
w <- scan_live(A3)
if (length(w) == 0L) {
  ok("A3_no_false_positive_no_emoji", "이모지 없음 → 무경보")
} else {
  bad("A3_no_false_positive_no_emoji", sprintf("오경보: %s", paste(w, collapse = " | ")))
}

#──────────────────────────────────────────────────────────────────────────────
# B축 — 위반 주입(진짜 미지원 entity 는 반드시 발화 + 정확히 지목)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[B] 위반 주입 = 발화 + 정확한 지목\n")

# B1: escape 된 &lt; 뒤, 한글 사이에 진짜 &nbsp;
B1 <- paste0(EMO, " 문턱 < 1.0 이며 여백&nbsp;문자가 섞였습니다.")
n <- named(scan_live(B1))
if (identical(n, "&nbsp;")) {
  ok("B1_nbsp_named", "&nbsp; 정확히 지목")
} else {
  bad("B1_nbsp_named", sprintf("기대 '&nbsp;' / 실제 [%s]", paste(n, collapse = ", ")))
}

# B2: &copy;
B2 <- paste0(EMO, " 판정 < 기준. 저작권&copy;표기 포함 한글 문장.")
n <- named(scan_live(B2))
if (identical(n, "&copy;")) {
  ok("B2_copy_named", "&copy; 정확히 지목")
} else {
  bad("B2_copy_named", sprintf("기대 '&copy;' / 실제 [%s]", paste(n, collapse = ", ")))
}

# B3: ★마스킹 구성 — non-BMP 4개 뒤 '&le;' 바로 다음에 '&lt;' 를 둔다.
#     구판에선 &le; 의 추출 창(+4칸)이 정확히 '&lt;' 위에 떨어져 setdiff 에 걸러진다.
B3 <- paste0(EMO, "임계 &le;&lt; 문턱 비교입니다.")
n <- named(scan_live(B3))
if ("&le;" %in% n) {
  ok("B3_masked_entity_named", "마스킹 구성에서도 &le; 지목")
} else {
  bad("B3_masked_entity_named", sprintf("&le; 가 지목되지 않음 — 마스킹 재발 [%s]", paste(n, collapse = ", ")))
}

# B4: 서로 다른 미지원 entity 2종 → 둘 다
B4 <- paste0(EMO, " 값 < 1.0 · &nbsp;그리고&copy;둘 다 있습니다.")
n <- named(scan_live(B4))
if (all(c("&nbsp;", "&copy;") %in% n)) {
  ok("B4_multiple_named", paste(n, collapse = ", "))
} else {
  bad("B4_multiple_named", sprintf("기대 &nbsp;+&copy; / 실제 [%s]", paste(n, collapse = ", ")))
}

#──────────────────────────────────────────────────────────────────────────────
# C축 — 음성 기준: 구 로직은 같은 픽스처에서 **틀려야** 한다.
#        (여기가 통과해버리면 A/B 는 결함을 구별하지 못하는 공허한 검사다)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[C] 구 로직 대조 — 이 검사가 결함을 실제로 구별하는가\n")

lg <- scan_legacy(A1)
if (length(lg) > 0L) {
  ok("C1_legacy_false_positives", sprintf("구판은 A1 에서 오경보: [%s]", paste(lg, collapse = ", ")))
} else {
  bad("C1_legacy_false_positives", "구판이 A1 에서 조용함 — A1 이 오경보를 구별하지 못하는 픽스처(공허)")
}

lg <- scan_legacy(B3)
if (!("&le;" %in% lg)) {
  ok("C2_legacy_masks_real_entity", sprintf("구판은 &le; 를 못 지목: [%s]", paste(lg, collapse = ", ")))
} else {
  bad("C2_legacy_masks_real_entity", "구판이 &le; 를 지목함 — B3 이 마스킹을 구별하지 못하는 픽스처(공허)")
}

#──────────────────────────────────────────────────────────────────────────────
# D축 — 자기검증 계약: 스캐너가 내놓는 토큰은 반드시 entity 모양이어야 한다.
#        (모양이 깨진 토큰 = "위반 없음"이 아니라 색인기 고장 → 별도 경보 대상)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[D] 추출물 자기검증 계약\n")

allf <- list(A1 = A1, A2 = A2, A3 = A3, B1 = B1, B2 = B2, B3 = B3, B4 = B4)
bad_shape <- unlist(lapply(allf, function(f) { n <- named(scan_live(f)); n[!grepl(ENT_SHAPE, n)] }))
if (length(bad_shape) == 0L) {
  ok("D1_reported_tokens_are_entities", "전 픽스처 지목 토큰이 entity 모양")
} else {
  bad("D1_reported_tokens_are_entities", sprintf("모양 깨진 토큰: [%s]", paste(bad_shape, collapse = ", ")))
}

lg_shape <- unlist(lapply(allf, function(f) { n <- scan_legacy(f); n[!grepl(ENT_SHAPE, n)] }))
if (length(lg_shape) > 0L) {
  ok("D2_legacy_emits_corrupt_tokens", sprintf("구판 산출에 깨진 토큰 존재 → ③ 가드 발화 대상: [%s]", paste(lg_shape, collapse = ", ")))
} else {
  bad("D2_legacy_emits_corrupt_tokens", "구판이 깨진 토큰을 안 냄 — D1 이 공허한 검사")
}

#──────────────────────────────────────────────────────────────────────────────
# E축 — 회귀 고정: 실사고 원본 메시지 특성(비-ASCII 밀림)이 오프셋에 영향 없음
#──────────────────────────────────────────────────────────────────────────────
cat("\n[E] 오프셋 정합 (엔진 색인 단위)\n")
probe <- paste0(EMO, "가나다 &nbsp; 라마바")
p_true <- as.integer(gregexpr("&nbsp;", probe, fixed = TRUE)[[1]])
p_perl <- as.integer(gregexpr("&[A-Za-z][A-Za-z0-9]{0,9};", probe, perl = TRUE)[[1]])
p_tre  <- as.integer(gregexpr("&[a-zA-Z]+;", probe)[[1]])
if (identical(p_perl, p_true)) {
  ok("E1_perl_offsets_are_codepoints", sprintf("perl=%d == 실제=%d", p_perl, p_true))
} else {
  bad("E1_perl_offsets_are_codepoints", sprintf("perl=%d != 실제=%d", p_perl, p_true))
}
if (!identical(p_tre, p_true)) {
  ok("E2_tre_offsets_shift_by_nonbmp", sprintf("TRE=%d vs 실제=%d (밀림 %d = non-BMP 4개)", p_tre, p_true, p_tre - p_true))
} else {
  # 이 플랫폼/버전에선 TRE 도 코드포인트 색인 → C/D 축 음성 기준이 성립하지 않는다.
  bad("E2_tre_offsets_shift_by_nonbmp",
      "TRE 가 밀리지 않음 — 이 런타임에선 원 결함이 재현되지 않으므로 C/D 축 판정을 신뢰할 수 없음")
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "telegram_entity_scan", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
