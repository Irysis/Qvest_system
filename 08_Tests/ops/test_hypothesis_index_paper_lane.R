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

# ── T4/T5 ★격리 루트 (2026-08-22 감사 HLT-1/HLT-2 재작성)
#   구판은 T4a 가 **생산 hypothesis_index 를 재빌드**하고 T4b 가 **생산 method_registry 의
#   mtime 을 밀었다 되돌렸고**, T5 는 거기에 **가짜 method 를 직접 주입**했다.
#   그 창에서 같은 배터리의 후속 3 스위트(risk_lane_verdict·nearest_arm_axis·Σ 어댑터)가
#   그 가짜 method 를 **실물 등재 항목으로 소비**했고, 크래시 시 오염이 잔존해
#   **다음 회차 배터리의 시작 상태**가 됐다(그래서 구 T5b 가 loop1·loop2 양쪽에서
#   참양성 FAIL 을 냈다 — flake 가 아니었다).
#   검사하는 명제("원천 목록에 method_registry 가 있는가" / "등재가 재빌드로 조회에
#   노출되는가")는 **루트 무관**이므로 임시 루트에서 물으면 같은 것을 재고
#   생산 부작용이 사라진다. 빌더의 원천 7종은 전부 file.exists/dir.exists 가드라
#   method_registry 사본 하나로 빌드가 성립한다.
mrp <- "06_Registry/method_registry.json"
prod_fp0     <- tools::md5sum(mrp)[[1]]
prod_idx_fp0 <- tools::md5sum(HI_INDEX_PATH)[[1]]

sbx <- file.path(tempdir(), sprintf("hi_paper_lane_%s_%d", Sys.getpid(), sample.int(1e6, 1)))
dir.create(file.path(sbx, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
sbx_mrp <- file.path(sbx, "06_Registry", "method_registry.json")
sbx_idx <- file.path(sbx, "06_Registry", "hypothesis_index.json")
file.copy(mrp, sbx_mrp, overwrite = TRUE)

# ── T4 ★stale 원천에 논문 레인이 포함된다 (행동 검사 — 소스 문자열 아님)
#     소스를 grep 하면 정당한 리팩터에 거짓 FAIL 이 난다(3회 실측). 발화를 본다.
#   ★T4a 는 **먼저 인덱스를 최신화한 뒤** 물어야 한다: 그냥 물으면 인덱스가 정말로
#   뒤처져 있을 때 stale 이 뜼는데 그건 오탐이 아니라 정탐이라, "검출기 고장"과
#   "legitimately stale" 을 구분하지 못해 배터리가 간헐적으로 빨개진다.
invisible(suppressMessages(build_hypothesis_index(root = sbx, out_path = sbx_idx,
                                                  verbose = FALSE)))
s0 <- .hi_stale_check(sbx_idx, root = sbx, warn = FALSE)
chk("T4a 재빌드 직후에는 stale 없음(오탐 아님을 그때 판정)", length(s0) == 0L,
    if (length(s0)) paste(s0, collapse=", ") else "")
Sys.setFileTime(sbx_mrp, Sys.time() + 5)
s1 <- .hi_stale_check(sbx_idx, root = sbx, warn = FALSE)
chk("T4b ★method_registry 갱신이 stale 로 검출된다", any(grepl("method_registry", s1)),
    sprintf("→ %s", paste(s1, collapse=", ")))

# ── T5 ★검출 → 자동 재빌드 → 조회 노출까지 이어지는가 (검출만 되고 반영 안 되면 무의미)
ok5 <- FALSE; ok5_err <- ""
tryCatch({
  m2 <- fromJSON(sbx_mrp, simplifyVector = FALSE)
  m2$methods <- c(m2$methods, list(list(
    method_id = "ZZ_PROBE_PAPER_LANE", paper_id = "arxiv:9999.99999",
    paper_title = "probe", route = "risk", adapter_kind = "sigma",
    adapter = "02_Infrastructure/methods/adapters/proper_score_gas.R",
    mechanism = "probe", kr_mapping = "probe", verdict = "implemented",
    selection_type = "chain", registered_at = "2026-08-13")))
  write(toJSON(m2, auto_unbox = TRUE, pretty = TRUE, null = "null"), sbx_mrp)
  Sys.setFileTime(sbx_mrp, Sys.time() + 5)
  invisible(suppressMessages(lookup_hypothesis("probe", index_path = sbx_idx, root = sbx)))
  sj <- fromJSON(sbx_idx, simplifyVector = FALSE)
  ok5 <- any(vapply(sj$entries,
                    function(e) identical(e$strategy_id, "PL_ZZ_PROBE_PAPER_LANE"), logical(1)))
}, error = function(e) { ok5_err <<- conditionMessage(e); cat("   (T5 예외:", ok5_err, ")
") })
unlink(sbx, recursive = TRUE, force = TRUE)

chk("T5 ★신규 등재가 자동 재빌드로 조회에 노출된다", ok5, ok5_err)
# ★T5b/c/d 재정의: 구판은 '내가 오염시킨 걸 내가 지웬나'(오염을 전제한 질문)를
#   물었다. 이젠 **애초에 생산 원장을 만지지 않았나** — 격리 계약 자체가 검사 대상이다.
chk("T5b ★격리 계약: 생산 method_registry 가 이 검사로 변하지 않는다",
    identical(prod_fp0, tools::md5sum(mrp)[[1]]), sprintf("md5 %s", substr(prod_fp0, 1, 12)))
chk("T5c ★격리 계약: 생산 hypothesis_index 가 이 검사로 변하지 않는다",
    identical(prod_idx_fp0, tools::md5sum(HI_INDEX_PATH)[[1]]),
    sprintf("md5 %s", substr(prod_idx_fp0, 1, 12)))
chk("T5d ★프로브가 생산 조회면에 새지 않는다",
    !any(vapply(pl_of()$pl, function(e) grepl("ZZ_PROBE", e$strategy_id), logical(1))))

# ── T6 측정 자동 조인 + 교란 경고가 수치와 **같은 자리에** 있다
meas <- Filter(function(e) !is.null(e$key_metrics$delta_ir), pl_of()$pl)
chk("T6 A/B 측정이 자동 조인된 항목이 있다", length(meas) > 0L, sprintf("%d건", length(meas)))
if (length(meas)) {
  # ★선택자를 **원천 문자열이 아니라 의미**로 (2026-08-13 재수리). 초판은 ab_source 가
  #   `h2_regime_overlay_ab.csv` 인 것만 골랐는데, regime 측정이 research_status 로 옮겨가자
  #   대상 0건이 되어 FAIL 했다 — 경고는 실제로 붙어 있는데 **선택자가 옛 원천에 박제**된 것.
  #   교란은 원천이 아니라 **노출 오버레이라는 성질**에서 나온다 ⇒ adapter_kind 로 고른다.
  ov <- Filter(function(e) identical(e$key_metrics$adapter_kind, "exposure"), meas)
  chk("T6b ★exposure(노출 오버레이) 측정은 교란 경고를 동반한다(따로 조회해야 알면 dead 배관)",
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

# ── T8 ★측정 **원천**이 둘 다 살아 있는가 (2026-08-13 N6)
#   측정치는 두 곳에서 온다: research_status(dispatch 기록) · A/B CSV. 하나가 조용히 끊기면
#   측정 건수만 줄고 **아무 소리도 안 난다**(오늘 실제로 risk 4건이 그렇게 사라져 있었다 —
#   콜렉터가 CSV 만 읽던 시절). 원천 목록은 상수(HI_PAPER_AB_SOURCES)+코드인데 그걸 묻는 축이
#   없었다. ⇒ **두 원천이 각각 최소 1건씩 기여하는지**를 축으로 세운다.
#   ★초판은 "두 원천이 모두 ≥1건 기여" 로 썼는데 그건 **유효한 불변식이 아니다** —
#     한 원천이 다른 것을 포섭하면 정당하게 0이 된다(실제로 regime arms 신설 후 csv 가 0이 되며
#     FAIL 했다). 의도는 "원천이 조용히 끊기지 않는다" 였다.
#     ⇒ **커버리지**로 다시 쓴다: 어느 원천에든 측정 기록이 있는 등재 method 는 인덱스에서도
#       반드시 measured 여야 한다. 원천 하나가 끊기면 그 method 가 커버리지에서 빠져 빨개진다.
.src_ids <- character(0)
for (p in sort(Sys.glob("stage_artifacts/paper_recharge/research_status_*.json"), decreasing = TRUE)) {
  jj <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL); if (is.null(jj)) next
  for (ln in names(jj$actions %||% list()))
    for (a in (jj$actions[[ln]]$verdict$arms %||% list()))
      if (isTRUE(a$measured)) .src_ids <- c(.src_ids, as.character(a$method_id %||% "")[1])
}
for (cf in c("06_Registry/book_carrier/h2_regime_overlay_ab.csv",
             "06_Registry/book_carrier/h1b_sigma_ab_overlay.csv")) {
  if (!file.exists(cf)) next
  tt <- tryCatch(utils::read.csv(cf, stringsAsFactors = FALSE), error = function(e) NULL)
  if (!is.null(tt) && "scenario" %in% names(tt)) .src_ids <- c(.src_ids, as.character(tt$scenario))
}
.src_ids <- unique(.src_ids[nzchar(.src_ids)])
.reg_ids <- vapply(mr$methods %||% list(), function(m) as.character(m$method_id %||% "")[1], "")
.should  <- intersect(.reg_ids, .src_ids)
.is_meas <- vapply(pl_of()$pl, function(e)
  identical(e$verdict, "PAPER_LANE_MEASURED"), logical(1))
.meas_ids <- sub("^PL_", "", vapply(pl_of()$pl, function(e) e$strategy_id, "")[.is_meas])
.gap <- setdiff(.should, .meas_ids)
chk("T8 ★어느 원천에든 측정 기록이 있는 등재 method 는 인덱스에서도 measured (원천 무음 차단)",
    length(.should) > 0L && length(.gap) == 0L,
    sprintf("대상 %d · 누락 %d%s", length(.should), length(.gap),
            if (length(.gap)) sprintf(" ★%s", paste(head(.gap, 3), collapse = ",")) else ""))

# ── T9 ★텔레그램 중복차단이 **기본값**인가 (2026-08-13 N6)
#   `force=TRUE` 는 tg_agent_brief 의 중복차단(TTL 30분)을 끈다. 오늘 그것 때문에 같은 메시지가
#   재실행마다 나갔고 도훈이 적발했다. 기본을 FALSE 로 되돌렸지만 **그 기본값을 지키는 축이 없다**
#   — 누가 다시 TRUE 로 두어도 아무것도 빨개지지 않는다.
#   ★소스 grep 이 아니라 **표현식을 평가**한다(리팩터에 거짓 FAIL 나지 않게).
#   ★최상위 스캔으로는 못 찾는다 — 그 대입은 `if (…NO_TG…) { }` **블록 안**에 있다.
#     초판이 그래서 NA 를 받아 **주입해도 안 잡히는 죽은 축**이었다(정상/주입 모두 NA).
#     규칙-축 대응을 감사하는 라운드에서 죽은 축을 만들 뻔했다 — 재귀로 훑는다.
.find_assign <- function(x, target) {
  if (is.call(x)) {
    if (length(x) >= 3 && identical(as.character(x[[1]])[1], "<-") &&
        identical(as.character(x[[2]])[1], target)) return(list(x[[3]]))
    return(unlist(lapply(as.list(x), .find_assign, target = target), recursive = FALSE))
  }
  NULL
}
.tgf <- tryCatch({
  ex <- parse(file.path(.root, "02_Infrastructure/ops/paper_research_dispatch.R"))
  rhs <- unlist(lapply(as.list(ex), .find_assign, target = ".TG_FORCE"), recursive = FALSE)
  old <- Sys.getenv("QVEST_DISPATCH_TG_FORCE", unset = NA_character_)
  Sys.unsetenv("QVEST_DISPATCH_TG_FORCE")            # 기본 환경에서 평가
  got <- if (length(rhs)) eval(rhs[[1]], envir = new.env(parent = globalenv())) else NA
  if (!is.na(old)) Sys.setenv(QVEST_DISPATCH_TG_FORCE = old)
  got
}, error = function(e) NA)
chk("T9 ★기본 환경에서 tg force=FALSE (중복 발송 억제가 기본값)",
    isFALSE(.tgf), sprintf("평가값 %s", as.character(.tgf)))

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"hypothesis_index_paper_lane","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
