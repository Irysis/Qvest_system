# test_refine_statement.R — 정제기 활성화 게이트 R0~R6 검출력 검사 (v9.1 커밋13, 2026-08-23)
#
# 무엇을 재는가
# -------------
# `02_Infrastructure/axiom/refine_statement.R` 의 R0~R6 가 **실제로 무엇을 잡는가**.
#
#   [A] 기준선   합성 픽스처가 R0~R6 전부 통과 → REFINED  (양성 대조)
#   [B] 위반 주입 5축 — 각 축이 **그 게이트만** 떨어뜨리는가
#         ① polarity 뒤집기      → R0
#         ② 멤버 결측 주입        → R1
#         ③ next_probe/live_trigger 제거 → R5
#         ④ falsification attempts 비우기 → R4
#         ⑤ 중복 공리 삽입        → R6
#   [C] 돌연변이 통제 — 게이트 판정을 **항상 TRUE** 로 바꾼 판본에서 위 5축이 전부
#       통과하는가. 통과하지 않으면 [B]의 검출이 게이트가 아니라 다른 데서 나온 것이다.
#   [D] 실저장소 분포 — active/modes/** 전건 판정이 **전부 HELD 도 전부 REFINED 도 아닌가**.
#
# ★검사 규율: "전부 HELD" 는 "게이트 로직이 죽었다" 와 겉보기가 같다. 그래서 이 검사의
#   본체는 개별 판정이 아니라 **분포**다 — [C] 돌연변이 통제가 없으면 [B]는 자기충족이다.
#
# 실행: Rscript 08_Tests/axiom/test_refine_statement.R
suppressPackageStartupMessages({ library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
skp <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT) || !dir.exists(ROOT)) {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  ROOT <- if (length(f)) normalizePath(file.path(dirname(f[1]), "..", "..")) else getwd()
}
RS_PATH <- file.path(ROOT, "02_Infrastructure", "axiom", "refine_statement.R")
if (!file.exists(RS_PATH)) {
  skp("T0_refiner_missing", RS_PATH)
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP)); quit(status = 0L)
}

.load_refiner <- function(path) {
  had <- Sys.getenv("REFINE_SOURCED", NA_character_)
  Sys.setenv(REFINE_SOURCED = "1")
  on.exit(if (is.na(had)) Sys.unsetenv("REFINE_SOURCED") else Sys.setenv(REFINE_SOURCED = had), add = TRUE)
  e <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(sys.source(path, envir = e)))
  e
}
E <- .load_refiner(RS_PATH)
ok("T0_load", "refine_statement.R 적재")
FN <- tryCatch(E$.rs_resolve_fals_norm(NULL, ROOT), error = function(e) NULL)
chk("T0_fals_norm", is.function(FN),
    sprintf("반증 토큰 정규화 함수 해석 (promote.R::.fals_norm_result 재사용=%s)",
            !isTRUE(attr(FN, "rs_fallback"))))

# ── 픽스처 ──────────────────────────────────────────────────────────────────
# win 4 / loss 4, 판별 토큰은 tag:OVERLAY_ON(win) vs tag:OVERLAY_OFF(loss) 로 lift ±1.0.
.mk_lc <- function(i, arm) {
  list(l_code = sprintf("L-TEST-%02d", i),
       record_type = "performance",
       grade = if (arm == "win") c("A", "B")[(i %% 2L) + 1L] else c("C", "F")[(i %% 2L) + 1L],
       family = "overlay_regime",
       construction_type = if (i %% 2L == 0L) "composite" else "chain",
       metric_type = if (arm == "win") "backtested" else "canonical_screen",
       selection_type = "hypothesis_chain",
       tags = if (arm == "win") list("OVERLAY_ON", "KR") else list("OVERLAY_OFF", "KR"),
       fmt_codes = if (arm == "loss") list("FMT-01") else list(),
       next_probe = sprintf("탐침 %d — 국면 조건부 재측정으로 %s 팔을 분리 재확인", i, arm),
       live_trigger = if (i == 1L) "regime_category in c('CRISIS')" else NULL,
       oos_retention = 0.6, portfolio_alpha_t = 1.2)
}
CORPUS <- list(lcodes = c(lapply(1:4, .mk_lc, arm = "win"), lapply(5:8, .mk_lc, arm = "loss")))
BASE <- list(
  axiom_id = "AX-TEST-001", research_mode = "alpha_research", cluster_key = "0123456789ab",
  type = "methodological", polarity = "conditional",
  statement = "테스트 기준선", status = "proposed",
  supporting_l_codes = as.list(sprintf("L-TEST-%02d", 1:8)),
  scope = list(market = "KR", factor_family = "overlay_regime"),
  evidence = list(constructions = list("composite", "chain")),
  falsification = list(attempts = list(
    list(test = "lag1 스트레스", result = "survived", effect_retained = 0.8, detail = "유지"),
    list(test = "strict-PIT A/B", result = "falsified", effect_retained = -0.1, detail = "붕괴"))),
  mechanism = list(mechanism_type = "behavioral",
                   economic_explanation = paste("국면 전환 직후 오버레이 노출 수준이 성과를 가르며,",
                                                "타이밍 기여는 잔여 14%에 그친다. 위기 구간에서만",
                                                "방어 팔이 켜지고 확장 구간에서는 꺼진다.")),
  oos_validation = list(oos_effect_vs_is = 0.42))

.run <- function(env, ax, corpus = CORPUS, peers = list())
  env$refine_statement(ax, corpus = corpus, fals_norm = FN, peers = peers, root = ROOT)
.gate <- function(r, g) isTRUE(r$gates[[g]]$pass)
GATES <- c("R0_polarity", "R1_members", "R2_tokens", "R3_mechanism",
           "R4_falsification", "R5_revival", "R6_distinct")

# ── [A] 기준선 ──────────────────────────────────────────────────────────────
cat("\n[A] 기준선 — 픽스처가 R0~R6 전부 통과하는가 (양성 대조)\n")
r0 <- .run(E, BASE)
chk("A1_baseline_refined", identical(r0$verdict, "REFINED"),
    sprintf("verdict=%s failing=%s", r0$verdict, paste(unlist(r0$failing), collapse = ",")))
chk("A2_baseline_all_gates", all(vapply(GATES, function(g) .gate(r0, g), logical(1))),
    paste(vapply(GATES, function(g) sprintf("%s=%s", sub("_.*", "", g), .gate(r0, g)), character(1)), collapse = " "))
chk("A3_statement_has_falsification_ledger", grepl("falsified", r0$statement, fixed = TRUE),
    "S6 반증 결산이 문장의 필수 구성요소 — 빠지면 자기 증거가 반증한 규칙을 무조건문으로 광고하게 된다")
chk("A4_statement_no_fixed_axis", !grepl("long-only|15bps|K200|Σw|25종|\\[0, ?0\\.20\\]", r0$statement),
    "S3 범위절에 고정 축 7종 미포함 (INV-7 제약 방화벽)")
chk("A5_lengths", nchar(r0$statement) <= 600L && nchar(r0$statement_inject) <= 70L,
    sprintf("statement %d<=600 · inject %d<=70", nchar(r0$statement), nchar(r0$statement_inject)))
chk("A6_deterministic", identical(.run(E, BASE)$statement, r0$statement) &&
      identical(.run(E, BASE)$refine_input_sha, r0$refine_input_sha),
    "같은 입력 → 같은 문장·같은 sha (결정적 조립. 아니면 held_stale 회계가 성립하지 않는다)")

# ── [B] 위반 주입 5축 ───────────────────────────────────────────────────────
cat("\n[B] 위반 주입 5축 — 각 축이 '그 게이트만' 떨어뜨리는가\n")
INJ <- list()
INJ$R0_polarity <- local({ a <- BASE; a$polarity <- "positive"; list(ax = a, corpus = CORPUS, peers = list()) })
INJ$R1_members  <- local({ a <- BASE
  a$supporting_l_codes <- c(a$supporting_l_codes, as.list(sprintf("L-GHOST-%02d", 1:8)))
  list(ax = a, corpus = CORPUS, peers = list()) })
INJ$R5_revival  <- local({ cp <- CORPUS
  cp$lcodes <- lapply(cp$lcodes, function(x) { x$next_probe <- NULL; x$next_probes <- NULL; x$live_trigger <- NULL; x })
  list(ax = BASE, corpus = cp, peers = list()) })
INJ$R4_falsification <- local({ a <- BASE; a$falsification <- list(attempts = list()); list(ax = a, corpus = CORPUS, peers = list()) })
INJ$R6_distinct <- local({ dup <- BASE; dup$axiom_id <- "AX-TEST-999"; dup$cluster_key <- "ffffffffffff"
  dup$promotion <- list(source_candidate = "CAND_other"); dup$status <- "active"
  list(ax = BASE, corpus = CORPUS, peers = list(dup)) })

inj_res <- list()
for (g in names(INJ)) {
  z <- INJ[[g]]
  r <- .run(E, z$ax, corpus = z$corpus, peers = z$peers)
  inj_res[[g]] <- r
  fl <- unlist(r$failing)
  chk(sprintf("B_%s_held", g), identical(r$verdict, "HELD"),
      sprintf("verdict=%s failing=%s", r$verdict, paste(fl, collapse = ",")))
  chk(sprintf("B_%s_targeted", g), identical(sort(fl), g),
      sprintf("표적 게이트만 미달이어야 한다 (실제: %s)", paste(sort(fl), collapse = ",")))
}
# R2/R3 은 5축 주입 대상이 아니다 — 전 주입에서 **통과 상태로 살아 있어야** 한다.
#   (조용히 상시 FALSE 면 위 targeted 검사가 통째로 무너진 것을 못 본다.)
chk("B6_R2_R3_alive_everywhere",
    all(vapply(inj_res, function(r) .gate(r, "R2_tokens") && .gate(r, "R3_mechanism"), logical(1))),
    "R2/R3 은 5축 주입과 무관하므로 전 케이스에서 TRUE 여야 한다")
# 분포 자체를 단언 — 유니크 실패 게이트 집합이 정확히 5종.
chk("B7_distribution", identical(sort(unique(unlist(lapply(inj_res, function(r) unlist(r$failing))))),
                                 sort(names(INJ))),
    sprintf("실패 게이트 집합 = %s", paste(sort(unique(unlist(lapply(inj_res, function(r) unlist(r$failing))))), collapse = ",")))

# ── [C] 돌연변이 통제 ───────────────────────────────────────────────────────
cat("\n[C] 돌연변이 통제 — 게이트 판정을 항상 TRUE 로 바꾸면 [B]의 검출이 죽는가\n")
src <- readLines(RS_PATH, warn = FALSE, encoding = "UTF-8")
hit <- grepl("^\\s+R[0-6]_[A-Za-z]+\\s*=\\s*list\\(pass = ", src)
if (sum(hit) != 7L) {
  bad("C0_mutant_build", sprintf("gates 블록의 `pass = ` 줄 %d개 탐지(기대 7) — 구조가 바뀌었으면 이 검사를 갱신할 것", sum(hit)))
} else {
  ok("C0_mutant_build", "gates 7줄 식별 → pass = TRUE || <원식> 으로 치환")
  src[hit] <- sub("list\\(pass = ", "list(pass = TRUE || ", src[hit])
  mp <- file.path(tempdir(), "refine_statement_MUTANT.R")
  writeLines(src, mp, useBytes = TRUE)
  M <- tryCatch(.load_refiner(mp), error = function(e) NULL)
  if (is.null(M)) {
    bad("C1_mutant_load", "돌연변이 판본 적재 실패")
  } else {
    ok("C1_mutant_load", basename(mp))
    surv <- character(0)
    for (g in names(INJ)) {
      z <- INJ[[g]]
      rm_ <- tryCatch(.run(M, z$ax, corpus = z$corpus, peers = z$peers),
                      error = function(e) list(verdict = paste0("ERROR:", conditionMessage(e))))
      if (!identical(rm_$verdict, "REFINED")) surv <- c(surv, sprintf("%s→%s", g, rm_$verdict))
    }
    chk("C2_mutant_kills_detection", !length(surv),
        if (length(surv))
          sprintf("돌연변이인데도 여전히 HELD: %s — [B]의 검출이 게이트가 아닌 다른 경로에서 나온다는 뜻",
                  paste(surv, collapse = " "))
        else "5축 전부 REFINED 로 뒤집힘 = [B]의 검출은 확실히 R0~R6 가 만든 것")
    rb <- tryCatch(.run(M, BASE), error = function(e) NULL)
    chk("C3_mutant_baseline_unchanged", !is.null(rb) && identical(rb$verdict, "REFINED"),
        "돌연변이 판본에서도 기준선은 REFINED (치환이 조립기 자체를 깨뜨리지 않았다)")
  }
  try(unlink(mp), silent = TRUE)
}

# ── [D] 실저장소 분포 ───────────────────────────────────────────────────────
cat("\n[D] 실저장소 분포 — 전부 HELD 도 전부 REFINED 도 아닌가\n")
axd <- file.path(ROOT, "qepm", "memory", "axioms", "active", "modes")
fs <- if (dir.exists(axd)) list.files(axd, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE) else character(0)
if (!length(fs)) {
  skp("D1_repo_distribution", "active/modes/** 공리 0건 — 분포 검사 대상 없음")
} else {
  rc <- tryCatch(E$.rs_load_corpus(ROOT), error = function(e) NULL)
  if (is.null(rc)) {
    skp("D1_repo_distribution", ".cache/lcode_corpus.json 부재 — 환경 문제이지 검사 실패가 아님")
  } else {
    docs <- Filter(Negate(is.null), lapply(fs, function(f) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)))
    vd <- vapply(docs, function(d) {
      self <- as.character(d$axiom_id %||% "")[1]
      pr <- Filter(function(p) !identical(as.character(p$axiom_id %||% "")[1], self), docs)
      tryCatch(.run(E, d, corpus = rc, peers = pr)$verdict, error = function(e) "ERROR")
    }, character(1))
    n_ref <- sum(vd == "REFINED"); n_held <- sum(vd == "HELD"); n_err <- sum(vd == "ERROR")
    cat(sprintf("      분포: REFINED=%d HELD=%d ERROR=%d (총 %d)\n", n_ref, n_held, n_err, length(vd)))
    chk("D1_no_error", n_err == 0L, sprintf("판정 중 예외 %d건", n_err))
    chk("D2_not_all_held", n_ref >= 1L,
        sprintf("REFINED=%d — 0 이면 게이트가 닫힌 것(구 5축 728회 0건 상태와 겉보기가 같다)", n_ref))
    chk("D3_not_all_refined", n_held >= 1L,
        sprintf("HELD=%d — 0 이면 게이트가 상시-통과(무인 활성화에서 가장 위험한 상태)", n_held))
  }
}

cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"refine_statement","pass":%d,"fail":%d,"skip":%d,"total":%d}\n',
            PASS, FAIL, SKIP, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
