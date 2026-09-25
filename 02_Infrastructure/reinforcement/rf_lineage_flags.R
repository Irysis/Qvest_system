#==============================================================================
# rf_lineage_flags.R — 계보 표식 술어 **정본** (P0-14 · 2026-09-25 · 관문 시점 계보 기반 표식 자동 승계)
#
# ★왜 파일로 뽑았나: A 자격 관문(rf_runner_gates.R::rf_a_eligibility) ⑤ vintage_flag 는 원장 attempt$vintage_flags 만 봤다.
#   표식은 **사후**에 붙는다(P0-08 apply_p0_08_flags.R · C11 봉쇄 rf_mark_vintage_batch) — 수집 시점의 새 칸에는 없다.
#   최고 계보 RP_20260917_105807_22632_* 167칸이 전부 selection_basis_full_sample_ic_inherited 표식으로 A 보류인데, 러너를
#   재개하면 이 계보의 새 칸(같은 팩터 집합 carry)은 표식 없이 A 관문을 통과한다. 그래서 관문이 **같은 사실을 스스로 재도출**한다.
#   ★자격 술어는 소비자의 함수여야 한다: P0-08 표식 스크립트(derive)와 관문이 **같은 함수**를 쓴다 — 사본 금지.
#     derive 가 쓰는 술어(rflf_fids · rflf_code · rflf_is_rule_cell · rflf_b7_misspecified · rflf_inherits)는 전부 여기 있고,
#     스크립트는 이 파일을 source 한다(스크래치 p0_14/tools/apply_p0_08_flags.R — 재도출 CSV 가 구판과 바이트 동일함을 실측).
#
# 두 재도출 (판정 = 여기 순수 함수 · 부작용 없음 · 읽기만):
#   (a) 선정 기저 승계 — 오염 집합 S = 원장(L1·L2)의 selection_basis_full_sample_ic **자기 표식** 칸(B1 규칙 선정기 전표본 선정)의
#       팩터 집합 ∪ spec$selection_basis == "full_sample_ic" 인 규칙 선정 칸의 집합. 칸 팩터 중 as-of 출처로 증명되지 않은 부분이
#       S 의 원소를 포함하면 selection_basis_full_sample_ic_inherited(자기 선정 전표본이면 selection_basis_full_sample_ic).
#       ★S 를 계보 재귀로만 찾지 않는 이유(실측 2026-09-25 원장): 승계 표식 501칸 중 291칸(58%)은 계보(entry + parent 사슬) 어디에도
#         자기 표식 칸이 없다 — 22632 계보 167칸 전부가 그렇다(오염 집합 {C03_EPS_Chg_3m} 은 다른 entry 의 규칙 선정기가 골랐다).
#         derive 의 승계 판정도 전역 포함(apply_p0_08_flags.R: sets = 전 원장 자기 표식 집합)이다 — 관문이 계보만 보면 derive 와
#         다른 사실을 낸다. 계보 재귀는 **면제 쪽**(as-of 출처 증명)에만 쓴다: 칸 팩터 중 as-of 규칙 선정기가 고른 것
#         (spec$selection_basis == "asof_ic" 칸의 carry 밖 팩터 · entry 안 선행 칸 · 부모 계보의 as-of 팩터 ∩ carry)은 오염 판정에서 뺀다.
#       ★as-of 구분 필드 = spec$selection_basis (rf_factor_arms.R::rf_pick_factor_sets 셀 필드 · 러너 SPEC 가 P0-14 부터 싣는다).
#         그 전 칸은 필드가 없다 — derive 는 opened_at < 신판 설치 시각으로 갈랐고(표식에 반영됨), 관문은 필드가 없으면 as-of 를
#         증명하지 못한 것으로 본다(보수 — 오염 포함 판정만 받는다). 설계 레인(LLM) 칸은 필드가 없다(R2 소관 · 남은 위험).
#   (b) C11 격리 — 칸이 06_Registry/pit_quarantine.json 효력 항목을 쓰는가: 팩터 id(factors·factor2/3·defense_sleeve.factor_id·
#       beta_factor) ∩ pitq_factor_ids · 격리 원천 정규식(pitq_source_hits) ← spec **전문**(toJSON — 알려지지 않은 구조 키까지) +
#       오버레이 arm 코드(overlay_arms/<kind>.R·.arm.json · 층 전부 = 자기 층 + carry·바닥 승계 층) + 기저 엔진 코드(base_signal
#       path/paths · 충실구현 engine_path) · entry$base_vintage_flags 의 격리 flag(기저 측정 자체가 격리).
#       ★spec 전문 스캔 = remeasure_from_holdings.R::rfh_pit_screen(rebase 비편입 판정)과 같은 범위. 자유 서술(idea·basis)의 원천 이름도
#         걸린다(보수 — 서술에 격리 원천을 적은 칸은 보류). 실측(2026-09-25 원장 사본 측정 1212칸): 전문 스캔 오탐 0 · 재도출 36 = pit_c11 표식 36.
#       등재 관문(rf_factor_pool · rf_overlay_admit · overlay_catalog suspended · rf_sleeve)이 **새 선정**을 막는다 — 여기는 그 뒤의
#       방어 심층이다: carry·바닥(.wbest_spec)·B4 조립은 등재 관문을 지나지 않고 부모/선행 칸의 구성을 그대로 싣는다.
#
# ★P0-14 수리 2판(2026-09-25 · 적대검증 PIT·시스템 BLOCKING):
#   ① as-of 면제는 **오염 집합 단위**다 — 오염 집합의 원소 전부가 as-of 로 증명돼야 그 집합이 빠진다. 구판은 칸 팩터에서 증명 id 를 먼저
#      빼고 포함을 봐서, 다른 칸이 원소 하나만 as-of 로 골라도 집합 전체가 면제됐다({FA,FB} 오염 + {FA} as-of 증명 → 통과).
#   ② 부모 계보 증명은 **carry 출처 칸(부모 승자 · carry$source_spec → source_cell)까지**만 본다 — carry 는 그 칸의 구성이다. 승격 뒤에 잰
#      부모 칸은 carry 의 선정 이력이 아니다. 출처 칸을 못 찾으면 부모 증명 없음(보수).
#   ③ 규칙 라벨 칸(N팩터 직교()인데 selection_basis 가 asof_ic 가 아니면(full_sample_ic · 부재 · 그 밖) **자기 표식**이다 — 격자 스냅샷
#      폴백(reinforce_auto_parallel.R factor_arms_fallback · 스냅샷 basis '… substrate 2026-07-31' = 전기간 선정)이 필드 없이 돌았다.
#      오염 집합 S 도 같은 기준(측정 · 원장 표식 없음 · 규칙 라벨 · as-of 아님)으로 넓힌다 — 실원장에서는 해당 칸이 전부 P0-08 자기 표식이라 S 불변.
#   ④ 재도출 입력 판독 불가(칸 spec 선언인데 파일 부재·파손 · spec·engine_path 둘 다 없음 · 선언 엔진 파일 부재 · carry 출처 칸을 원장에서
#      못 찾음) = unreadable → 관문 보류.
#      파생 표식은 원장에 적지 않으므로(설계 (c)) 재평가 때 spec 이 사라지면 보류가 풀렸다(fail-open).
#   ⑤ tick 캐시는 원장 entries 가 바뀌면 다시 계산한다(구판 키 = root 만 — 첫 호출 entries 고정).
#   ★정정(출처): 22632 계보의 C03_EPS_Chg_3m 은 11800 규칙 선정기에서 **carry 된 것이 아니다** — 22632 루트 자신의 B1 LLM 설계 칸 rev_3m 이
#     골랐다. 보류는 전역 포함 판정(S 에 11800 규칙 선정기가 전표본으로 고른 {C03} 이 있다) 때문이다. 이 과잉 보류의 완화(설계·문헌 출처를
#     어떻게 볼지)는 도훈 결정 사안이다(R2 as-of 증명 필드로 풀리는 경로가 아니다).
#
# 공개: rflf_fids · rflf_code · rflf_is_rule_cell · rflf_b7_misspecified · rflf_inherits (derive 공용 술어)
#       rflf_contaminated_sets · rflf_clean_ids · rflf_selection_derive · rflf_c11_derive · rflf_gate_flags (관문 재도출)
#       rflf_marks_plan (원장 기록 계획 — 순수 · 쓰기는 호출자가 rf_mark_vintage_batch 로)
# 요구: jsonlite · (C11) 02_Infrastructure/validation/pit_quarantine.R(데이터 루트 → 코드 루트 순)
# 검사: 08_Tests/reinforcement/test_rf_a_gate_lineage_flags.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
.RFLF_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.rflf_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 표식 이름·정책 — derive(P0-08)와 같은 flag 어휘(원장 표식 레코드 허용목록은 flag 이름에 기저를 싣는다)
RFLF_FLAG_SELF    <- "selection_basis_full_sample_ic"
RFLF_FLAG_INHERIT <- "selection_basis_full_sample_ic_inherited"
RFLF_FLAG_C11     <- "pit_c11"
RFLF_POLICY <- "P0-14 derived — 관문 시점 계보 재도출(rf_lineage_flags.R) · 표식만 · 재측정 금지 · 2026-09-25"

# ── derive 공용 술어 (apply_p0_08_flags.R 에서 옮김 — 동작 비트 동일 · 그 스크립트가 이 함수를 부른다) ─────────────────
.rflf_chr <- function(x) { x <- as.character(unlist(.rflf_or(x, ""))); if (!length(x) || is.na(x[1])) "" else x[1] }

#' 칸 스펙의 DB 팩터 id 집합(정렬·중복 제거) — factors + factor2/factor3(kind != none) 중 kind 가 db(부재 = db)인 것
rflf_fids <- function(s) {
  if (is.null(s)) return(character(0))
  fs <- c(.rflf_or(s$factors, list()),
          if (!is.null(s$factor2) && !identical(.rflf_chr(s$factor2$kind), "none")) list(s$factor2),
          if (!is.null(s$factor3) && !identical(.rflf_chr(s$factor3$kind), "none")) list(s$factor3))
  sort(unique(vapply(Filter(function(f) is.list(f) && identical(.rflf_chr(.rflf_or(f$kind, "db")), "db"), fs),
                     function(f) .rflf_chr(f$id), "")))
}

#' 칸 코드 — attempt cell_code → essence cell_code
rflf_code <- function(a) { c1 <- .rflf_chr(a$cell_code); if (nzchar(c1)) c1 else .rflf_chr(.rflf_or(a$essence, list())$cell_code) }

#' B1 규칙 선정기(rf_pick_factor_sets) 칸인가 — 코드 B1_ 또는 idea "[무인 … B1_" · 라벨 "N팩터 직교(" (신·구판 라벨 동일)
rflf_is_rule_cell <- function(a, s) {
  cd <- rflf_code(a); idea <- .rflf_chr(a$idea)
  lab <- paste(.rflf_chr(.rflf_or(s$label, "")), idea)
  (startsWith(cd, "B1_") || grepl("^\\[무인 [^]]*B1_", idea)) && grepl("[0-9]팩터 직교\\(", lab)
}

#' B7 처치 오지정(P0-08 ①) — defense_sleeve · factor_id 미고정 · select = ic_bad_rank 또는 미지정(구 기본값) / B7 칸인데 스펙 판독 불가
#'   ★관문은 이것을 재도출하지 않는다: 신판 rf_sleeve.R 은 퇴역 select(ic_bad_rank)를 파싱에서 멈추고 미지정 기본값이 ic_bad_rank_asof 다 —
#'   새 칸은 이 처치를 받을 수 없다. derive(과거 칸) 전용.
#' @return list(hit, basis)
rflf_b7_misspecified <- function(a, s) {
  ds <- if (is.null(s)) NULL else s[["defense_sleeve"]]
  if (!is.null(ds) && !nzchar(.rflf_chr(ds$factor_id)) && .rflf_chr(.rflf_or(ds$select, "ic_bad_rank")) %in% c("ic_bad_rank", ""))
    return(list(hit = TRUE, basis = sprintf("defense_sleeve.select=%s kind=%s k=%s",
                                            .rflf_chr(.rflf_or(ds$select, "(미지정=구 기본 ic_bad_rank)")), .rflf_chr(ds$kind), .rflf_chr(ds$k))))
  if (is.null(ds) && startsWith(rflf_code(a), "B7_"))
    return(list(hit = TRUE, basis = "B7 칸인데 스펙 판독 불가 — 보수적 표식(구 규칙 시기 측정)"))
  list(hit = FALSE, basis = "")
}

#' 오염 집합 포함 — f 가 포함하는 sets 원소 전부(list · 비었으면 list()). 빈 집합은 sets 에 넣지 않는다(all(∅ %in% f) = TRUE).
rflf_inherits <- function(f, sets) Filter(function(sx) all(sx %in% f), .rflf_or(sets, list()))

# ── 판독 도우미 (캐시 = 호출자 환경 · NULL 도 캐시) ─────────────────────────────────────────────────────────────
.rflf_cached <- function(cache, key, f) {
  if (is.environment(cache) && exists(key, envir = cache, inherits = FALSE)) return(get(key, envir = cache, inherits = FALSE))
  v <- f()
  if (is.environment(cache)) assign(key, v, envir = cache)
  v
}
# 의존값(dep)이 같을 때만 재사용 — identical() 은 같은 객체면 즉시 참(C 수준 포인터 비교)이라 tick 안 반복 호출은 비용이 없다
.rflf_cached_on <- function(cache, key, dep, f) {
  if (is.environment(cache) && exists(key, envir = cache, inherits = FALSE)) {
    z <- get(key, envir = cache, inherits = FALSE)
    if (is.list(z) && identical(z$dep, dep)) return(z$val)
  }
  v <- f()
  if (is.environment(cache)) assign(key, list(dep = dep, val = v), envir = cache)
  v
}
.rflf_abs <- function(p, root) {
  p <- .rflf_chr(p); if (!nzchar(p)) return("")
  if (!grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)", p)) p <- file.path(root, p)
  p
}
.rflf_json_file <- function(p, cache = NULL) {
  if (!nzchar(p) || !file.exists(p)) return(NULL)
  .rflf_cached(cache, paste0("rflf_json|", p), function() tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL))
}
.rflf_text_file <- function(p, cache = NULL) {
  if (!nzchar(p) || !file.exists(p)) return(NULL)
  .rflf_cached(cache, paste0("rflf_txt|", p), function()
    tryCatch(paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), error = function(e) NULL))
}
# ★[["essence"]] 정확 일치 — $ 는 부분 일치라 essence 가 없고 essence_history 가 있으면 history 를 집는다(rf_runner_gates.R 과 같은 규약)
.rflf_spec_of <- function(a, root, cache = NULL) .rflf_json_file(.rflf_abs(.rflf_or(a[["essence"]], list())$spec, root), cache)
.rflf_measured <- function(a) {
  v <- suppressWarnings(as.numeric(.rflf_or(.rflf_or(a[["essence"]], list())$port_t, NA)))
  length(v) == 1L && is.finite(v)
}
.rflf_has_flag <- function(fl, flag) any(vapply(.rflf_or(fl, list()), function(z) identical(.rflf_chr(z$flag), flag), logical(1)))
.rflf_sb <- function(s) .rflf_chr(if (is.list(s)) s[["selection_basis"]] else NULL)
# 규칙 선정 후보 사전 거름(스펙 판독 전 — 코드·idea 만): 규칙 선정기 칸은 전부 B1 이다
.rflf_b1ish <- function(a) startsWith(rflf_code(a), "B1_") || grepl("^\\[무인 [^]]*B1_", .rflf_chr(a$idea))
.rflf_entries <- function(L) if (is.list(L) && !is.null(L$entries)) .rflf_or(L$entries, list()) else .rflf_or(L, list())

#' 원장 판독 — L1 = 호출자가 준 entries(러너 tick 원장 · 비었으면 root 파일) · L2 = root 파일. 반환 list(l1 = entries, l2 = entries)
rflf_ledgers <- function(root, entries = NULL, cache = NULL) {
  rd <- function(ly) .rflf_cached(cache, sprintf("rflf_ledger_l%d|%s", ly, root), function() {
    p <- file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", ly))
    if (!file.exists(p)) return(list())
    L <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) stop(sprintf("원장 L%d 파손 — 재도출 불가: %s", ly, p), call. = FALSE))
    .rflf_entries(L) })
  list(l1 = if (length(entries)) entries else rd(1L), l2 = rd(2L))
}

#' (a) 오염 집합 S — 자기 표식 칸의 팩터 집합 + 표식 없는 측정 규칙 라벨 칸 중 as-of 가 아닌 칸(spec selection_basis = full_sample_ic 선언 ·
#'   필드 부재 = 격자 스냅샷 폴백·P0-14 이전 러너 · 그 밖 값)의 집합(P0-14 수리 2판 ③ — 관문의 자기 표식 규칙과 같은 기준).
#'   스펙 판독 불가 자기 표식 칸 → 표식 source 의 "factors=A+B"(derive 기록 형식)로 폴백 → 그래도 없으면 unknown(호출자가 fail-closed).
#'   표식 없는 규칙 라벨 칸(idea 로 판별)인데 스펙 판독 불가 → 집합을 모른다 → unknown.
#' @return list(sets = list(character), n_self_marked, n_spec_declared, n_undeclared, unknown = character(<base_id#n>))
rflf_contaminated_sets <- function(ledgers, root, cache = NULL) {
  sets <- list(); unk <- character(0); n_m <- 0L; n_d <- 0L; n_u <- 0L
  add <- function(f) if (length(f)) sets[[length(sets) + 1L]] <<- f
  for (ly in c("l1", "l2")) for (e in .rflf_or(ledgers[[ly]], list())) for (a in .rflf_or(e$attempts, list())) {
    fl <- .rflf_or(a$vintage_flags, list())
    if (.rflf_has_flag(fl, RFLF_FLAG_SELF)) {
      n_m <- n_m + 1L
      f <- rflf_fids(.rflf_spec_of(a, root, cache))
      if (!length(f)) {
        src <- .rflf_chr(Filter(function(z) identical(.rflf_chr(z$flag), RFLF_FLAG_SELF), fl)[[1]]$source)
        m <- regmatches(src, regexpr("factors=[A-Za-z0-9_+]+", src))
        if (length(m)) f <- sort(unique(strsplit(sub("^factors=", "", m), "+", fixed = TRUE)[[1]]))
      }
      if (length(f)) add(f) else unk <- c(unk, sprintf("%s#%s", .rflf_chr(e$base_id), .rflf_chr(a$n)))
      next
    }
    if (!.rflf_measured(a) || !.rflf_b1ish(a)) next
    s <- .rflf_spec_of(a, root, cache)
    if (!rflf_is_rule_cell(a, s) || identical(.rflf_sb(s), "asof_ic")) next
    f <- rflf_fids(s)
    if (!length(f)) { unk <- c(unk, sprintf("%s#%s(규칙 라벨 · 스펙 판독 불가)", .rflf_chr(e$base_id), .rflf_chr(a$n))); next }
    if (identical(.rflf_sb(s), "full_sample_ic")) n_d <- n_d + 1L else n_u <- n_u + 1L
    add(f)
  }
  keys <- vapply(sets, paste, character(1), collapse = "+")
  list(sets = sets[!duplicated(keys)], n_self_marked = n_m, n_spec_declared = n_d, n_undeclared = n_u, unknown = unk)
}

#' carry 출처 칸의 n — 부모 entry P 에서 carry 를 낳은 칸(rf_promote_carry: carry$source_spec = 부모 승자 칸 essence$spec · 실원장 승격 17/17 일치)
#'   → 없으면 carry$source_cell / parent$cell 코드. 같은 칸이 여럿이면 가장 큰 n. 못 찾으면 NA(부모 증명 승계 없음 — 호출자가 보수 처리).
.rflf_np <- function(p) tolower(gsub("\\", "/", .rflf_chr(p), fixed = TRUE))
.rflf_carry_src_n <- function(E, P) {
  cr <- .rflf_or(E$carry, list()); ss <- .rflf_np(cr$source_spec)
  sc <- .rflf_chr(cr$source_cell); if (!nzchar(sc)) sc <- .rflf_chr(.rflf_or(E$parent, list())$cell)
  ns <- function(pred) { v <- numeric(0)
    for (a in .rflf_or(P$attempts, list())) { n <- suppressWarnings(as.numeric(.rflf_or(a$n, NA)))
      if (length(n) == 1L && is.finite(n) && isTRUE(pred(a))) v <- c(v, n) }
    v }
  v <- if (nzchar(ss)) ns(function(a) identical(.rflf_np(.rflf_or(a[["essence"]], list())$spec), ss)) else numeric(0)
  if (!length(v) && nzchar(sc)) v <- ns(function(a) identical(rflf_code(a), sc))
  if (length(v)) max(v) else NA_real_
}

#' (a) as-of 출처로 증명된 팩터 id — entry 안(n < before_n)의 as-of 규칙 선정 칸이 고른 팩터(carry 밖) ∪ (부모 계보의 증명 id ∩ carry)
#'   carry 는 부모 승자 구성이다(rf_promote_carry) — 부모에서 as-of 로 증명된 팩터만 carry 를 건너 증명이 이어진다.
#'   ★부모 쪽 증명은 carry 출처 칸 n 이하에서만(P0-14 수리 2판 ② — 승격 뒤 부모 칸은 carry 의 선정 이력이 아니다 · 출처 못 찾으면 증명 없음).
rflf_clean_ids <- function(entries, bid, root, before_n = Inf, cache = NULL, depth = 0L, seen = character(0), max_depth = 20L) {
  bid <- .rflf_chr(bid); if (!nzchar(bid) || bid %in% seen || depth > max_depth) return(character(0))
  E <- Filter(function(x) identical(.rflf_chr(x$base_id), bid), .rflf_or(entries, list()))
  if (!length(E)) return(character(0))
  E <- E[[1]]
  carryF <- rflf_fids(E$carry)
  own <- character(0)
  for (a in .rflf_or(E$attempts, list())) {
    n <- suppressWarnings(as.numeric(.rflf_or(a$n, NA)))
    if (!is.finite(n) || n >= before_n || !.rflf_b1ish(a)) next
    s <- .rflf_spec_of(a, root, cache)
    if (identical(.rflf_sb(s), "asof_ic") && rflf_is_rule_cell(a, s)) own <- union(own, setdiff(rflf_fids(s), carryF))
  }
  pid <- .rflf_chr(.rflf_or(E$parent, list())$base_id)
  par <- character(0)
  if (nzchar(pid) && length(carryF)) {
    PE <- Filter(function(x) identical(.rflf_chr(x$base_id), pid), .rflf_or(entries, list()))
    w <- if (length(PE)) .rflf_carry_src_n(E, PE[[1]]) else NA_real_
    if (is.finite(w))
      par <- intersect(rflf_clean_ids(entries, pid, root, w + 1, cache, depth + 1L, c(seen, bid), max_depth), carryF)
  }
  sort(union(own, par))
}

#' (a) 칸 1개의 선정 기저 재도출
#' @return list(flag = NULL|RFLF_FLAG_SELF|RFLF_FLAG_INHERIT, sets = 걸린 오염 집합, fids, clean, basis, selection_basis)
rflf_selection_derive <- function(entry, attempt, spec, entries, S, root, cache = NULL) {
  f <- rflf_fids(spec); sb <- .rflf_sb(spec)
  out <- list(flag = NULL, sets = list(), fids = f, clean = character(0), basis = "", selection_basis = sb)
  if (!length(f)) return(out)
  rule <- rflf_is_rule_cell(attempt, spec)
  # ★규칙 라벨 칸은 as-of 선언이 있을 때만 자기 선정 면제 후보다(P0-14 수리 2판 ③) — 필드 부재 = 격자 스냅샷 폴백·P0-14 이전 러너(전표본).
  if (rule && !identical(sb, "asof_ic")) {
    out$flag <- RFLF_FLAG_SELF; out$sets <- list(f)
    out$basis <- if (identical(sb, "full_sample_ic")) sprintf("규칙 선정기 spec selection_basis=full_sample_ic · factors=%s", paste(f, collapse = "+"))
                 else sprintf("규칙 라벨 칸인데 selection_basis=%s — as-of 선정 증명 없음(격자 스냅샷 폴백 등) = 전표본으로 본다 · factors=%s",
                              if (nzchar(sb)) sb else "(없음)", paste(f, collapse = "+"))
    return(out)
  }
  carryF <- rflf_fids((.rflf_or(entry, list()))$carry)
  own <- if (rule && identical(sb, "asof_ic")) setdiff(f, carryF) else character(0)
  n <- suppressWarnings(as.numeric(.rflf_or(attempt$n, NA))); if (!is.finite(n)) n <- Inf
  lin <- rflf_clean_ids(entries, .rflf_chr((.rflf_or(entry, list()))$base_id), root, before_n = n, cache = cache)
  clean <- sort(union(own, lin)); out$clean <- clean
  # ★면제는 집합 단위(P0-14 수리 2판 ①): 칸이 포함하는 오염 집합 중 원소 전부가 as-of 증명인 것만 뺀다.
  hit <- Filter(function(sx) !all(sx %in% clean), rflf_inherits(f, S$sets))
  if (length(hit)) {
    out$flag <- RFLF_FLAG_INHERIT; out$sets <- hit
    out$basis <- sprintf("승계 집합 %s ⊆ factors(as-of 증명 %d종 제외 · selection_basis=%s)",
                         paste(hit[[1]], collapse = "+"), length(clean), if (nzchar(sb)) sb else "(없음)")
  }
  out
}

# ── (b) C11 격리 ────────────────────────────────────────────────────────────────────────────────────────────
#' 격리 판독기 적재(데이터 루트 → 코드 루트) — 목록이 있는데 판독기가 없으면 stop(조용한 해제 금지 · rf_factor_arms 와 같은 규약)
.rflf_pitq <- function(root, cache = NULL) .rflf_cached(cache, paste0("rflf_pitq|", root), function() {
  rel <- "02_Infrastructure/validation/pit_quarantine.R"
  lib <- unique(c(file.path(root, rel), file.path(.RFLF_ROOT(), rel))); lib <- lib[file.exists(lib)]
  if (!length(lib)) {
    if (file.exists(file.path(root, "06_Registry/pit_quarantine.json")))
      stop("[rf_lineage_flags] pit_quarantine.json 은 있는데 판독기(pit_quarantine.R)가 없다 — 격리를 건너뛰지 않는다", call. = FALSE)
    return(list(factors = character(0), regex = character(0), flags = character(0)))
  }
  en <- new.env(parent = globalenv()); sys.source(lib[1], envir = en, keep.source = FALSE)
  items <- en$pitq_load(root)   # 파손 = stop(판독기 규약)
  fl <- unique(c(RFLF_FLAG_C11, vapply(items, function(x) .rflf_chr(x$flag), character(1))))
  list(factors = en$pitq_factor_ids(root), regex = en$pitq_source_regex(root), flags = fl[nzchar(fl)])
})
.rflf_rx_hits <- function(txt, rx) {
  if (!length(rx) || is.null(txt) || !nzchar(txt)) return(character(0))
  rx[vapply(rx, function(r) isTRUE(grepl(r, txt, perl = TRUE, ignore.case = TRUE)), logical(1))]
}
.rflf_ov_layers <- function(x) {
  if (is.null(x) || !is.list(x)) return(list())
  if (!is.null(x$kind)) return(list(x))
  out <- list(); for (z in x) if (is.list(z)) out <- c(out, .rflf_ov_layers(z)); out
}

#' (b) 칸 1개의 C11 격리 재도출
#' @param engine_paths 추가 엔진 경로(충실구현 어댑터 — attempt$engine_path)
#' @return list(hit, factors, sources = list(<출처> = 걸린 정규식), base_flag, scanned = 스캔한 출처 수,
#'              unreadable = 선언됐는데 읽지 못한 엔진 경로(호출자가 fail-closed — P0-14 수리 2판 ④))
rflf_c11_derive <- function(entry, attempt, spec, root, cache = NULL, engine_paths = NULL) {
  Q <- .rflf_pitq(root, cache)
  out <- list(hit = FALSE, factors = character(0), sources = list(), base_flag = character(0), scanned = 0L, unreadable = character(0))
  sp <- if (is.list(spec)) spec else list()
  ds <- sp[["defense_sleeve"]]
  fid <- unique(c(rflf_fids(sp), if (is.list(ds)) c(.rflf_chr(ds$factor_id), .rflf_chr(ds$beta_factor))))
  fid <- fid[nzchar(fid)]
  out$factors <- intersect(fid, Q$factors)
  L <- .rflf_ov_layers(sp[["overlay"]])
  bs <- sp[["base_signal"]]
  eng <- unique(c(if (is.list(bs)) c(.rflf_chr(bs$path), vapply(.rflf_or(bs$paths, list()), .rflf_chr, character(1))),
                  vapply(.rflf_or(engine_paths, list()), .rflf_chr, character(1))))
  eng <- eng[nzchar(eng)]
  # spec 전문(직렬화 — 파일 없이 넘어온 list 도 같은 텍스트) + 충실구현 엔진 경로(spec 이 없다)
  src <- list(spec = paste(c(if (length(sp)) as.character(toJSON(sp, auto_unbox = TRUE, null = "null")), eng), collapse = "\n"))
  ad <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms")
  for (k in unique(vapply(L, function(z) .rflf_chr(z$kind), character(1)))) {
    if (!nzchar(k) || grepl("[/\\\\]", k)) next
    for (f in file.path(ad, paste0(k, c(".R", ".arm.json")))) { t <- .rflf_text_file(f, cache); if (!is.null(t)) src[[paste0("arm:", basename(f))]] <- t }
  }
  for (p in eng) { t <- .rflf_text_file(.rflf_abs(p, root), cache)
    if (!is.null(t)) src[[paste0("engine:", basename(p))]] <- t else out$unreadable <- c(out$unreadable, p) }
  out$scanned <- length(src)
  for (nm in names(src)) { h <- .rflf_rx_hits(src[[nm]], Q$regex); if (length(h)) out$sources[[nm]] <- h }
  bf <- vapply(.rflf_or((.rflf_or(entry, list()))$base_vintage_flags, list()), function(z) .rflf_chr(z$flag), character(1))
  out$base_flag <- intersect(bf, Q$flags)
  out$hit <- length(out$factors) > 0L || length(out$sources) > 0L || length(out$base_flag) > 0L
  out
}

#' 관문 재도출 — 칸 1개의 파생 표식 레코드(원장 표식과 같은 모양 {flag, verdict, evidence, source} + derived = TRUE)
#'   이미 원장 표식에 같은 flag 가 있으면 내지 않는다(중복 없음 — 원장 표식이 정본이고 재도출은 빈 곳만 메운다).
#' @param ctx rf_a_ctx() 결과(root · cache · entries) — 캐시는 tick 단위(ctx$cache)
#' @return list(flags = list(레코드), selection = rflf_selection_derive 결과, c11 = rflf_c11_derive 결과, S_unknown,
#'              unreadable = 재도출 입력 판독 불가 사유(칸 spec 선언인데 판독 불가 · spec·engine_path 둘 다 없음 · 선언 엔진 판독 불가) —
#'              관문이 보류한다(fail-closed · P0-14 수리 2판 ④ · 파생 표식은 원장에 없으므로 재평가 때 spec 이 사라져도 보류가 유지돼야 한다))
rflf_gate_flags <- function(entry, attempt, spec, ctx, engine_paths = NULL) {
  root <- .rflf_or(ctx$root, .RFLF_ROOT()); cache <- ctx$cache
  have <- vapply(.rflf_or(attempt$vintage_flags, list()), function(z) .rflf_chr(z$flag), character(1))
  flags <- list(); sel <- NULL; S_unk <- character(0); unread <- character(0)
  spd <- .rflf_chr(.rflf_or(attempt[["essence"]], list())$spec)
  eng_decl <- vapply(.rflf_or(engine_paths, list()), .rflf_chr, character(1)); eng_decl <- eng_decl[nzchar(eng_decl)]
  if (!is.list(spec) && nzchar(spd)) unread <- c(unread, sprintf("칸 spec 판독 불가(%s)", spd)) else
    if (!is.list(spec) && !length(eng_decl)) unread <- c(unread, "칸 spec·engine_path 모두 없음 — 재도출 대상 불명")
  mk <- function(flag, evidence, source) list(flag = flag, verdict = "consumed", evidence = evidence, source = source, derived = TRUE)
  cd <- rflf_code(attempt); if (!nzchar(cd) && is.list(spec)) cd <- .rflf_chr(spec$code)
  if (length(rflf_fids(spec))) {
    # ★캐시는 entries 가 같을 때만(P0-14 수리 2판 ⑤ · identical = 같은 객체면 즉시 참) — 구판 키는 root 만이라 첫 호출 entries 가 tick 끝까지 고정됐다.
    Lg <- .rflf_cached_on(cache, paste0("rflf_ledgers|", root), ctx$entries, function() rflf_ledgers(root, ctx$entries, cache))
    S <- .rflf_cached_on(cache, paste0("rflf_S|", root), Lg, function() rflf_contaminated_sets(Lg, root, cache))
    S_unk <- S$unknown
    # ★carry 출처를 원장에서 못 찾으면(부모 entry 부재 · 출처 칸 부재) carry 구성의 선정 이력을 모른다 = 판독 불가(수리 2판 ④ · 적대검증 PIT C3 —
    #   부모 칸이 원장에 없으면 그 칸들이 S 에 들지 못해 carry 된 전표본 집합이 조용히 통과했다). 실원장 승격 17/17 은 출처가 잡힌다.
    cfE <- rflf_fids((.rflf_or(entry, list()))$carry)
    if (length(cfE)) {
      pidE <- .rflf_chr((.rflf_or((.rflf_or(entry, list()))$parent, list()))$base_id)
      PEE <- if (nzchar(pidE)) Filter(function(x) identical(.rflf_chr(x$base_id), pidE), .rflf_or(Lg$l1, list())) else list()
      if (!length(PEE) || !is.finite(.rflf_carry_src_n(entry, PEE[[1]])))
        unread <- c(unread, sprintf("carry 출처 판독 불가(parent=%s · %s) — carry 구성 {%s} 의 선정 이력을 원장에서 찾지 못함",
                                    if (nzchar(pidE)) pidE else "(없음)", if (length(PEE)) "출처 칸 없음" else "부모 entry 없음",
                                    paste(cfE, collapse = ",")))
    }
    sel <- rflf_selection_derive(entry, attempt, spec, Lg$l1, S, root, cache)
    # 원장에 선정 기저 표식(자기·승계 어느 쪽이든)이 이미 있으면 같은 사실을 다시 내지 않는다 — 자기 표식 칸은 자기 집합을 포함하므로
    # 재도출은 늘 '승계'를 낸다(실원장 60칸). 판정은 원장 표식이 이미 보류시키고, 기록 계획(rflf_marks_plan)에 중복 표식이 생기지 않는다.
    if (!is.null(sel$flag) && !any(c(RFLF_FLAG_SELF, RFLF_FLAG_INHERIT) %in% have))
      flags[[length(flags) + 1L]] <- mk(sel$flag,
        if (identical(sel$flag, RFLF_FLAG_SELF)) "B1 규칙 선정기 전표본 선정(spec selection_basis=full_sample_ic) — pit.md C1 D-E · 플랜 P0-08 표식 규약"
        else "B1 규칙 선정기 전표본 선정 팩터 집합을 carry/바닥/설계로 승계한 칸(as-of 출처 증명 없음) — pit.md C1 D-E · P0-08 derive 와 같은 술어",
        sprintf("P0-14 derived · %s · %s", cd, sel$basis))
  }
  c11 <- rflf_c11_derive(entry, attempt, spec, root, cache, engine_paths)
  if (length(c11$unreadable)) unread <- c(unread, sprintf("엔진 판독 불가(%s)", paste(c11$unreadable, collapse = ",")))
  if (isTRUE(c11$hit) && !(RFLF_FLAG_C11 %in% have)) {
    why <- c(if (length(c11$factors)) sprintf("factors=%s", paste(c11$factors, collapse = "+")),
             if (length(c11$sources)) sprintf("sources=%s", paste(sprintf("%s[%s]", names(c11$sources),
                                                                             vapply(c11$sources, paste, character(1), collapse = "|")), collapse = ";")),
             if (length(c11$base_flag)) sprintf("base_vintage_flags=%s", paste(c11$base_flag, collapse = "+")))
    flags[[length(flags) + 1L]] <- mk(RFLF_FLAG_C11,
      "06_Registry/pit_quarantine.json 효력 항목(격리 팩터·원천·기저) 사용 — 결정 PIT-C11-CONVENTIONS ⑧(오염 선택은 보유 재측정으로 씻기지 않는다)",
      sprintf("P0-14 derived · %s · %s", cd, paste(why, collapse = " · ")))
  }
  list(flags = flags, selection = sel, c11 = c11, S_unknown = S_unk, unreadable = unread)
}

#' 원장 기록 계획(순수 · 쓰기 0) — 측정 칸 중 재도출 표식이 원장에 아직 없는 칸의 표식 목록(rf_mark_vintage_batch marks 형식).
#'   ★러너 tick 안에서 쓰지 않는다: rf_mark_vintage_batch 는 러너 claim 을 새로 잡는다 — 같은 프로세스가 쥔 claim 이면 'claimed' 로
#'     wait_s(900초) 대기 후 거부된다(재진입 모드 없음 · 검사 L1 실증). 기록은 러너 idle 창에서 이 계획 + writer 로(멱등: 같은 flag 는 건너뛴다).
#' @param only_after ISO8601 — 이 시각 이후 연 칸만(과거 칸은 P0-08·C11 표식이 이미 덮었다). NULL = 전 측정 칸.
rflf_marks_plan <- function(layer = 1L, root = .RFLF_ROOT(), only_after = NULL, ctx = NULL) {
  ctx <- .rflf_or(ctx, list(root = root, cache = new.env(parent = emptyenv()), entries = NULL))
  Lg <- rflf_ledgers(root, NULL, ctx$cache); ctx$entries <- Lg$l1
  E <- if (identical(as.integer(layer), 2L)) Lg$l2 else Lg$l1
  cut <- if (is.null(only_after)) NA_real_ else
    as.numeric(as.POSIXct(sub("([+-][0-9]{2}):?([0-9]{2})$", "\\1\\2", only_after), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"))
  marks <- list()
  for (e in E) for (a in .rflf_or(e$attempts, list())) {
    if (!.rflf_measured(a)) next
    if (is.finite(cut)) {
      t <- as.numeric(as.POSIXct(sub("([+-][0-9]{2}):?([0-9]{2})$", "\\1\\2", .rflf_chr(a$opened_at)), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"))
      if (!is.finite(t) || t < cut) next
    }
    g <- rflf_gate_flags(e, a, .rflf_spec_of(a, root, ctx$cache), ctx)
    for (z in g$flags) marks[[length(marks) + 1L]] <- list(base_id = .rflf_chr(e$base_id), attempt_key = .rflf_chr(a$n),
                                                          flag = z$flag, verdict = z$verdict, evidence = z$evidence, source = z$source)
  }
  marks
}

if (sys.nframe() == 0L)
  cat("[rf_lineage_flags.R] Loaded (P0-14) — rflf_fids / rflf_is_rule_cell / rflf_b7_misspecified / rflf_inherits / rflf_contaminated_sets / rflf_clean_ids / rflf_selection_derive / rflf_c11_derive / rflf_gate_flags / rflf_marks_plan\n")
