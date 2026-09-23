#==============================================================================
# pit_quarantine.R — PIT 위반 격리 목록 판독기 (2026-09-24 · C11 봉쇄 · 판정서 안 A 0단계)
#
# 왜: pit.md '위반 시 처리' 1단계(즉시 중단)·2단계(결과 무효)를 코드 수리·이력 재빌드 **전에** 집행한다.
#   오염 원천(팩터 빌더·국면 패널)을 고치는 일은 도훈 결정(06_Registry/decision_register.json#PIT-C11-REMEDIATION)
#   뒤다. 그 사이 무인 레인이 오염 신호를 **새로** 소비하지 않게 하는 것이 이 목록의 일이다.
#   코드에 id 를 박지 않고 목록 파일을 소비자가 읽게 한 이유: 해제·추가가 코드 편집 없이 되고,
#   사유·판정서·결정 참조·원값이 한 파일에 남는다(되돌리는 법도 거기 적는다).
#
# 정본 = 06_Registry/pit_quarantine.json — quarantines[] 의 status == "active" 인 항목만 효력.
#   factors[].id   : 강화 팩터 후보 풀에서 뺄 팩터 id
#   sources[].regex: 생성 arm 코드가 참조하면 등재를 거부할 원천(패널 파일·팩터 id) — perl · 대소문자 무시
#
# 소비자:
#   · 02_Infrastructure/ops/rf_factor_arms.R::rf_factor_pool         (B1 규칙 선정 · B1 설계 재료 · b1_verify 공통 정본)
#   · 02_Infrastructure/reinforcement/rf_overlay_admit.R::rf_overlay_admit (생성 오버레이 arm 등재 관문)
#
# 실패 규약: 파일 부재 = 격리 0(해제 상태) · 파손/형식 불량 = stop — 조용히 해제하지 않는다.
#   (호출부의 폴백은 각 소비자 규약: rf_factor_pool 실패 → 러너 factor_pick_failed → 격자 스냅샷 셀 ·
#    등재 관문 실패 → 그 arm REJECT 로 방출 원장에 기록)
# 검사 = 08_Tests/validation/test_pit_quarantine_c11.R (양성 대조 + 위반 주입 + 돌연변이 red)
#==============================================================================
.pitq_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

pitq_path <- function(root) file.path(root, "06_Registry/pit_quarantine.json")

#' 효력 있는 격리 항목 목록. 부재 = list() · 파손/형식 불량 = stop.
pitq_load <- function(root) {
  p <- pitq_path(root)
  if (!file.exists(p)) return(list())
  d <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) e)
  if (inherits(d, "error"))
    stop("[pit_quarantine] 파손 — 격리 목록을 읽지 못했다(조용히 해제하지 않는다): ", p, " · ",
         conditionMessage(d), call. = FALSE)
  q <- d$quarantines
  if (!is.list(q) || !length(q))
    stop("[pit_quarantine] 형식 불량 — quarantines 배열이 없다(해제는 항목 status 로 한다): ", p, call. = FALSE)
  Filter(function(x) is.list(x) && identical(as.character(.pitq_or(x$status, "active"))[1], "active"), q)
}

#' 격리된 팩터 id (효력 항목 전체의 합집합)
pitq_factor_ids <- function(root) {
  v <- unlist(lapply(pitq_load(root), function(x)
    vapply(.pitq_or(x$factors, list()), function(f) as.character(.pitq_or(f$id, ""))[1], character(1))))
  v <- unique(as.character(v)); v[!is.na(v) & nzchar(v)]
}

#' 격리 원천 정규식 (효력 항목 전체의 합집합)
pitq_source_regex <- function(root) {
  v <- unlist(lapply(pitq_load(root), function(x)
    vapply(.pitq_or(x$sources, list()), function(s) as.character(.pitq_or(s$regex, ""))[1], character(1))))
  v <- unique(as.character(v)); v[!is.na(v) & nzchar(v)]
}

#' 텍스트가 참조하는 격리 원천 — 걸린 정규식 벡터(없으면 character(0))
pitq_source_hits <- function(text, root) {
  rx <- pitq_source_regex(root)
  if (!length(rx)) return(character(0))
  txt <- paste(as.character(text), collapse = "\n")
  rx[vapply(rx, function(r) isTRUE(grepl(r, txt, perl = TRUE, ignore.case = TRUE)), logical(1))]
}
