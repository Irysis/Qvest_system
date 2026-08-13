#!/usr/bin/env Rscript
# test_hypothesis_index_paper_lane.R — 논문 레인 → hypothesis_index 소비면 계약 (2026-08-13 신설)
#
# 왜: 도훈 지시로 레인의 종착이 확정됐다 — 논문 라우팅은 **가능성을 보는 단계**이고, 1차 리서치
#   후 **각 리서치 모드가 조회할 수 있는 형태**로 인덱스에 올려두는 것까지가 레인의 일이다.
#   그 전까지 인덱스 빌더 원천 6종에 method_registry 가 없어 **등재 어댑터 16건이 모드에게
#   보이지 않았다** — 큐를 아무리 드레인해도 소비면이 닫혀 있었다.
#
# ★이 검사의 본체는 T4/T5 다: **콜렉터가 있는 것만으로는 부족하다.**
#   stale 원천 목록에 method_registry 가 없으면 어댑터를 등재해도 인덱스가 뒤처진 채로 남고
#   lookup 이 **옛 인덱스를 조용히 서빙**한다. 즉 "만들었다"와 "다음 칸이 읽는다"는 다른 칸이고,
#   이 저장소가 반복 확인한 결함이 정확히 그 사이에서 난다.
set.seed(20260813)
.root <- (function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
})()
setwd(.root)
suppressWarnings(suppressMessages({
  library(jsonlite)
  source("02_Infrastructure/tools/hypothesis_index.R")
}))

PASS <- 0; FAIL <- 0
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1; cat(sprintf("  ok   %s %s\n", n, d)) }
                                 else { FAIL <<- FAIL + 1; cat(sprintf("  FAIL %s %s\n", n, d)) } }
pl_of <- function() {
  j <- fromJSON(HI_INDEX_PATH, simplifyVector = FALSE)
  list(all = j$entries, pl = Filter(function(e) grepl("^PL_", e$strategy_id), j$entries))
}
cat("== 논문 레인 → hypothesis_index 소비면 ==\n")

s <- pl_of()
chk("T1 논문 레인 항목이 인덱스에 존재한다", length(s$pl) > 0L,
    sprintf("PL_ %d / 전체 %d", length(s$pl), length(s$all)))

# ── T2 등재 어댑터 수와 인덱스 항목 수가 맞는가 (조용한 드롭 방지)
mr <- fromJSON("06_Registry/method_registry.json", simplifyVector = FALSE)
n_m <- length(mr$methods %||% list())
chk("T2 등재 method 전건이 인덱스에 반영된다(조용한 드롭 0)", length(s$pl) == n_m,
    sprintf("registry %d vs index %d", n_m, length(s$pl)))

# ── T3 스키마 — 모드가 읽는 9필드가 전부 있다
req <- c("strategy_id","hypothesis_signature","title","verdict","grade",
         "key_metrics","source_paths","source_types","date")
miss <- unique(unlist(lapply(s$pl, function(e) setdiff(req, names(e)))))
chk("T3 필수 9필드 결손 없음", length(miss) == 0L,
    if (length(miss)) paste("결손:", paste(miss, collapse=",")) else "")
chk("T3b source_types 가 paper_lane 으로 식별된다",
    all(vapply(s$pl, function(e) "paper_lane" %in% unlist(e$source_types), logical(1))))

# ── T4 ★stale 원천에 논문 레인이 포함된다 (행동 검사 — 소스 문자열 아님)
#     소스를 grep 하면 정당한 리팩터에 거짓 FAIL 이 난다(오늘 3회 실측). 발화를 본다.
idx <- HI_INDEX_PATH
# ★T4a 는 **먼저 인덱스를 최신화한 뒤** 물어야 한다 (2026-08-13 수리).
#   초판은 그냥 물었는데, 디스패치가 A/B CSV 를 재생성한 직후에 돌면 인덱스가 **정말로**
#   뒤처져 있어서 stale 이 뜬다 — 그건 오탐이 아니라 정탐이다. 그 상태로 FAIL 을 내면
#   "검출기 고장"과 "인덱스가 legitimately stale"을 구분하지 못하고, 배터리가 디스패치
#   직후에만 간헐적으로 빨개진다(실측: 단독 10/1 → 재실행 11/11 × 3).
#   ⇒ 최신화 후에도 stale 이 뜨면 그때가 진짜 오탐이다.
invisible(suppressMessages(build_hypothesis_index(verbose = FALSE)))
s0 <- .hi_stale_check(idx, warn = FALSE)
chk("T4a 재빌드 직후에는 stale 없음(오탐 아님을 그때 판정)", length(s0) == 0L,
    if (length(s0)) paste(s0, collapse=", ") else "")
mrp <- "06_Registry/method_registry.json"
mt0 <- file.info(mrp)$mtime
Sys.setFileTime(mrp, Sys.time() + 5)
s1 <- .hi_stale_check(idx, warn = FALSE)
chk("T4b ★method_registry 갱신이 stale 로 검출된다", any(grepl("method_registry", s1)),
    sprintf("→ %s", paste(s1, collapse=", ")))
Sys.setFileTime(mrp, mt0)

# ── T5 ★검출 → 자동 재빌드 → 조회 노출까지 이어지는가 (검출만 되고 반영 안 되면 무의미)
orig <- readLines(mrp, warn = FALSE)
ok5 <- FALSE
tryCatch({
  m2 <- fromJSON(mrp, simplifyVector = FALSE)
  m2$methods <- c(m2$methods, list(list(
    method_id = "ZZ_PROBE_PAPER_LANE", paper_id = "arxiv:9999.99999",
    paper_title = "probe", route = "risk", adapter_kind = "sigma",
    adapter = "02_Infrastructure/methods/adapters/proper_score_gas.R",
    mechanism = "probe", kr_mapping = "probe", verdict = "implemented",
    selection_type = "chain", registered_at = "2026-08-13")))
  write(toJSON(m2, auto_unbox = TRUE, pretty = TRUE, null = "null"), mrp)
  Sys.setFileTime(mrp, Sys.time() + 5)
  invisible(suppressMessages(lookup_hypothesis("probe")))
  ok5 <- any(vapply(pl_of()$pl, function(e) identical(e$strategy_id, "PL_ZZ_PROBE_PAPER_LANE"), logical(1)))
}, error = function(e) cat("   (T5 예외:", conditionMessage(e), ")\n"))
writeLines(orig, mrp)
invisible(suppressMessages(build_hypothesis_index(verbose = FALSE)))
chk("T5 ★신규 등재가 자동 재빌드로 조회에 노출된다", ok5)
chk("T5b 원상복구 확인(주입 항목 제거됨)",
    !any(vapply(pl_of()$pl, function(e) grepl("ZZ_PROBE", e$strategy_id), logical(1))))

# ── T6 측정 자동 조인 + 교란 경고가 수치와 **같은 자리에** 있다
meas <- Filter(function(e) !is.null(e$key_metrics$delta_ir), pl_of()$pl)
chk("T6 A/B 측정이 자동 조인된 항목이 있다", length(meas) > 0L, sprintf("%d건", length(meas)))
if (length(meas)) {
  ov <- Filter(function(e) grepl("regime_overlay", e$key_metrics$ab_source %||% ""), meas)
  chk("T6b ★regime overlay 항목은 교란 경고를 동반한다(따로 조회해야 알면 dead 배관)",
      length(ov) > 0L && all(vapply(ov, function(e) nzchar(e$key_metrics$delta_ir_caveat %||% ""), logical(1))),
      sprintf("%d건 중 경고 동반 %d", length(ov),
              sum(vapply(ov, function(e) nzchar(e$key_metrics$delta_ir_caveat %||% ""), logical(1)))))
  # ★T6c 일반화 (2026-08-13 수리) — 원래 의도는 "avg_exposure 가 있어야 한다"가 아니라
  #   **"수치 옆에 그 수치를 읽는 데 필요한 맥락이 함께 있어야 한다"** 였다.
  #   맥락이 무엇인지는 원천이 정한다:
  #     · regime overlay A/B → `avg_exposure` (ΔIR 의 86%를 설명하는 교란 변수)
  #     · research_status(dispatch 기록) → `control` / `control_basis` (무엇과 비교했는가)
  #   초판은 avg_exposure 를 전건에 요구해서, risk 레인 arm(weight·sigma)이 붙자마자 FAIL 했다 —
  #   그 arm 들에는 노출 개념 자체가 없다. 필드를 박제하면 새 원천이 붙을 때 검사가 먼저 깨진다.
  ctx_ok <- vapply(meas, function(e) {
    k <- e$key_metrics
    if (grepl("regime_overlay", k$ab_source %||% "")) !is.null(k$avg_exposure)
    else !is.null(k$control_basis) || !is.null(k$control) || !is.null(k$avg_exposure)
  }, logical(1))
  chk("T6c 측정치 옆에 **읽는 맥락**이 함께 있다(overlay=노출 / dispatch=대조기준)",
      all(ctx_ok), sprintf("%d/%d", sum(ctx_ok), length(ctx_ok)))
}

# ── T7 ★대조 기준이 **kind 에 맞는가** (2026-08-13 N5 신설)
#   같은 method 를 레인마다 다른 대조로 잰다: risk=minvar_lw(Σ만 교체) / optimizer=strategy(북 전체)
#   / regime csv=book_L5. 아무거나 집으면 **측정은 그대로인데 숫자만 바뀐다**
#   (실측: ProperScoreGASFilter −0.219 vs −0.477). 그래서 kind 가 고르게 만들었는데,
#   그 선호표는 지금 **코드에만 있고 검사가 없었다** — sigma 가 strategy 대조로 뒤집혀도
#   기존 축은 전부 통과한다. 오늘 세 번 확인한 계통(검사 없는 규칙은 다음 확장에서 조용히 뒤집힘).
#   ★sigma 는 Σ 효과만 분리해야 하므로 minvar 계열 대조가 아니면 그 수치는 다른 것을 재고 있다.
meas2 <- Filter(function(e) !is.null(e$key_metrics$delta_ir), pl_of()$pl)
bad <- character(0)
for (e in meas2) {
  k <- e$key_metrics; ck <- tolower(k$control %||% k$measured_lane %||% "")
  ok <- switch(k$adapter_kind %||% "?",
               sigma    = grepl("minvar", ck),                       # Σ 교체만 분리
               weight   = grepl("strategy|book", ck),                # 북 전체 대비
               exposure = grepl("csv|regime|book", ck),              # 노출 스케줄 대비
               TRUE)
  if (!isTRUE(ok)) bad <- c(bad, sprintf("%s[%s]=%s", e$strategy_id, k$adapter_kind %||% "?", ck))
}
chk("T7 ★대조 기준이 adapter_kind 와 정합(sigma=minvar · weight=book · exposure=노출)",
    length(meas2) > 0L && length(bad) == 0L,
    if (length(bad)) sprintf("★불일치 %d: %s", length(bad), paste(head(bad, 3), collapse="; "))
    else sprintf("%d건 전건 정합", length(meas2)))
# T7b 여러 레인이 잰 경우 **대안을 숨기지 않는다** — 고르되 나머지를 기록해야 재판정이 가능하다
multi <- Filter(function(e) nzchar(e$key_metrics$other_lane_measurements %||% ""), meas2)
chk("T7b 복수 레인 측정은 other_lane_measurements 로 병기된다", length(multi) > 0L,
    sprintf("%d건", length(multi)))

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"hypothesis_index_paper_lane","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
