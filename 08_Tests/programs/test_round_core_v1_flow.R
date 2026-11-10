## test_round_core_v1_flow.R — 공통 판정 코어 v1 등록 · 판정 · 종료 흐름(격리 — 실제 등록부 · 원장 · stage_artifacts 에 쓰지 않는다)
##   초안 → 점검 기록 → 등록 거부 조건(점검 없음 · revise · 점검 뒤 초안 변경 · 초안 뒤 사양 변경 · 핀 변경 · P1 미수령 · 응답 없는 도전)
##   → 등록 → 판정(P1 틀 · P0R01 공유 측정) → 보는 창 파일(시험 창 열 · τ_D 이후 날짜 없음) → 종료 기록 · 칸 평가 캐시 키 민감도 · 핀 대조 어휘
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
source("04_Research/programs/_lib/round_core/v1/load.R")

SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_flow")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE), onexit = TRUE))  # r-portability 금칙 ②: 최상위 on.exit 는 no-op
Sys.setenv(RC_SA_ROOT = file.path(SB, "sa"))
REG <- file.path(SB, "research_programs.json"); invisible(file.copy("06_Registry/research_programs.json", REG))
LED <- file.path(SB, "ledger.json"); RVR <- file.path(SB, "rv")
RID <- "P1R99_core_selftest"; RD <- file.path(SB, "round", RID); dir.create(RD, recursive = TRUE)
PIN <- file.path(SB, "pinned.txt"); writeLines("고정 대상", PIN)
spec <- list(schema = "round_spec_v1", program = "P1_RETURN", round_id = RID, template = "p1_qualification", core_version = "v1", tau_d = "2022-12-31",
             purpose = "코어 자체 시험(격리)", hypothesis = "P1R01 규칙 재현",
             cells = lapply(c("E1", "E2", "E3"), function(e) list(code = sprintf("P0R01_%s_C0", e), engine = e, role = "variant",
                                                                 source_results = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")),
             rules = list(
               list(id = "qualify", type = "all_of", label = "수익 엔진 자격", na = "fail", of = list(
                 list(id = "q_t_alpha", type = "threshold", label = "보는 창 β-통제 t(α)", metric = "t_alpha_vis", op = ">=",
                      value_ref = "02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t", na = "fail"),
                 list(id = "q_uc", type = "threshold", label = "보는 창 상승 포착", metric = "uc_vis", op = ">=", value = 0.55,
                      basis = "투자철학 헌장 강세 참여 ≥ 55%", na = "fail"))),
               list(id = "test_hold", type = "report", label = "시험 창 유지", when = "qualify", metric = "alpha_ann_test", op = ">", value = 0,
                    basis = "사람 쪽 보고")),
             selection = list(rule = "none"), exposures = list("시험 창 성과를 본 상태(보고 전용)"), conclusion_scope = list("자체 시험"),
             pins = list(files = list(PIN)))
SPEC_TXT <- as.character(jsonlite::toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA))
writeLines(SPEC_TXT, file.path(RD, "round_spec.json"), useBytes = TRUE)
P <- rc_paths(RD, rc_spec_load(file.path(RD, "round_spec.json")))
reg <- function() rc_register(RD, registry_path = REG, ledger = LED, check_git = FALSE, review_root = RVR)
review <- function(v, verdict) { f <- file.path(SB, sprintf("review_v%d.md", v)); writeLines(paste("점검", v, verdict), f); rc_mark_reviewed(RD, v, f, verdict) }

cat("A 초안 · 점검 기록\n")
d1 <- rc_draft(RD)
md <- readLines(d1$md, encoding = "UTF-8")
chk("A1 초안 v1 · md 에 선언에서 만든 규칙 문장", d1$version == 1L && file.exists(P$draft) && any(grepl("t_alpha_vis >= 2", md)) && any(grepl("uc_vis >= 0.55", md)))
chk("A2 점검 없이 등록 = 거부", grepl("격리 점검을 받지 않았다", err_of(reg())))
review(1, "revise")
chk("A3 점검 판정 revise = 거부", grepl("ok 가 아니다", err_of(reg())))
d2 <- rc_draft(RD); review(2, "ok")
cat("x", file = P$draft, append = TRUE)
chk("A4 점검 뒤 초안 변경 = 거부", grepl("점검받지 않은 초안", err_of(reg())))
chk("A5 점검 기록은 디스크 초안이 그 판일 때만", grepl("가 아니다", err_of(review(2, "ok"))))
d3 <- rc_draft(RD); review(3, "ok")
writeLines(sub("코어 자체 시험(격리)", "바뀐 목적", SPEC_TXT, fixed = TRUE), file.path(RD, "round_spec.json"), useBytes = TRUE)
chk("A6 초안 뒤 사양 변경 = 거부", grepl("사양이 초안 뒤에 바뀌었다", err_of(reg())))
writeLines(SPEC_TXT, file.path(RD, "round_spec.json"), useBytes = TRUE)
writeLines("바뀐 내용", PIN)
chk("A7 핀 파일 변경 = 거부", grepl("핀 파일 md5 변경", err_of(reg())))
writeLines("고정 대상", PIN)

cat("B 철학 P1 수령\n")
jw <- function(x) writeLines(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = TRUE)), LED, useBytes = TRUE)
jw(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = list(), challenges = list()))
chk("B1 P1 리뷰 없음 = 거부", grepl("철학 P1 리뷰가 원장에 없다", err_of(reg())))
RVF <- "04_Research/programs/_supervision/superfan/philosophy/20261020_1200_P1_P1R99.md"
dir.create(dirname(file.path(RVR, RVF)), recursive = TRUE); writeLines("P1 리뷰", file.path(RVR, RVF))
rv <- list(id = "R-T-1", role = "philosophy", trigger = "P1", round = RID, file = RVF, challenges = list("C-T-1"))
jw(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = list(rv),
        challenges = list(list(id = "C-T-1", review = "R-T-1", grade = "challenge", status = "open", responses = list()))))
chk("B2 응답 없는 도전 = 거부", grepl("응답 없는 도전", err_of(reg())))
jw(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = list(rv),
        challenges = list(list(id = "C-T-1", review = "R-T-1", grade = "challenge", status = "accepted", responses = list(list(kind = "accept"))))))

cat("C 등록 · 판정 · 종료\n")
r <- tryCatch(reg(), error = function(e) e)
chk("C1 조건 충족 → 등록(두 사본 · 등록부)", !inherits(r, "error") && file.exists(P$prereg) && file.exists(P$prereg_copy) &&
      identical(rc_md5(P$prereg), rc_md5(P$prereg_copy)), if (inherits(r, "error")) conditionMessage(r) else "")
e1 <- Filter(function(z) identical(z$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)
chk("C2 등록부(임시 사본) 항목 · md5 · registered", length(e1) == 1L && identical(e1[[1]]$prereg_md5, rc_md5(P$prereg)) && identical(e1[[1]]$status, "registered"))
pre <- rc_json_read(P$prereg)
chk("C3 사전등록에 점검 판 목록(사본 없음) · P1 수령 · 코어 판", length(pre$reviewed_drafts) == 3L && isTRUE(pre$philosophy_p1$ok) &&
      identical(pre$core$version, "v1") && !length(list.files(RD, pattern = "reviewed_v")))
V <- tryCatch(rc_evaluate(RD, registry_path = REG), error = function(e) e)
chk("C4 판정(P1 틀) — 자격 E2 · E3(P1R01 과 같다)", !inherits(V, "error") && identical(sort(unlist(V$qualified)), c("E2", "E3")),
    if (inherits(V, "error")) conditionMessage(V) else paste(unlist(V$qualified), collapse = ","))
vis <- rc_json_read(file.path(P$results, "evaluation_visible.json"))
cols <- unique(unlist(lapply(vis$table, names)))
chk("C5 보는 창 파일 — 시험 창 열 없음 · τ_D 이후 날짜 없음", !any(grepl("_test$", cols)) && !length(rc_after_tau_leaks(vis, as.Date("2022-12-31"))),
    paste(cols, collapse = ","))
vj <- rc_json_read(file.path(P$results, "verdict.json"))
chk("C6 판정 기록 = 지금 사전등록 md5 · 요약 라벨", identical(vj$prereg_md5, rc_md5(P$prereg)) && grepl("^자격 2/3", vj$summary$label))
## 닫는 단계 기계화(2026-11-10 · v10.2 결과 원장) — 격리 등록부 옆에 원장이 생긴다(운영 06_Registry/round_outcomes.jsonl 무접촉)
OUTL <- rc_outcomes_path(registry_path = REG)
chk("C7a 다음 탐침 2개 미만 = 종료 거부(사유도 없으면)", grepl("다음 탐침이 2개 미만", err_of(rc_close(RD, note = "자체 시험", registry_path = REG, probes = "하나뿐"))) && !file.exists(OUTL))
chk("C7b 해석 글에 정보 경계 뒤 날짜 = 종료 거부 · 원장 · 등록부 무기록",
    grepl("정보 경계 뒤 날짜", err_of(rc_close(RD, note = "2024-03-15 급락에서 확인", registry_path = REG, probes = c("탐침 하나", "탐침 둘")))) && !file.exists(OUTL) &&
      !identical(Filter(function(z) identical(z$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)[[1]]$status, "complete"))
chk("C7c 목표 축 판독 어휘 밖 = 거부", grepl("어휘 밖", err_of(rc_close(RD, note = "자체 시험", registry_path = REG, probes = c("a", "b"), r7 = "maybe"))))
rc_close(RD, note = "자체 시험", registry_path = REG, probes = c("탐침 하나", "탐침 둘"), lessons = "교훈 하나", r7 = "noise")
e2 <- Filter(function(z) identical(z$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)
chk("C7 종료 기록 — complete · 판정 요약 · 해석 메모", identical(e2[[1]]$status, "complete") && grepl("^자격 2/3", e2[[1]]$verdict$label) &&
      identical(e2[[1]]$verdict$note, "자체 시험"))
o1 <- rc_outcomes_read(OUTL)
chk("C7d 결과 원장 1줄 — 라운드 · 프로그램 · 탐침 2 · 교훈 1 · 목표 축 판독 · 측정 축 · 사전등록 md5",
    length(o1) == 1L && identical(o1[[1]]$round_id, RID) && identical(o1[[1]]$program, "P1_RETURN") && length(o1[[1]]$probes) == 2L &&
      length(o1[[1]]$lessons) == 1L && identical(o1[[1]]$r7, "noise") && !is.null(o1[[1]]$epoch) && identical(o1[[1]]$prereg_md5, rc_md5(P$prereg)))
rc_close(RD, note = "자체 시험", registry_path = REG, probes = c("탐침 하나", "탐침 둘"))
chk("C7e 같은 라운드를 다시 닫아도 원장은 한 줄(추가 전용 · 중복 없음)", length(rc_outcomes_read(OUTL)) == 1L)
## 마감 훅(2026-11-10 · v10.2 · round_candidate_gate.R::rcg_finalize) — P1 틀은 최종 후보가 없다 · 마감 실패는 닫기를 막지 않는다
chk("C7m P1 틀 닫기 = 마감 훅 건너뜀(등록부 finalize = 'skip: 템플릿 p1_qualification…' · 결과 원장 = skip)",
    startsWith(as.character(e2[[1]]$finalize %||% ""), "skip: 템플릿 p1_qualification") && identical(o1[[1]]$finalize, "skip"),
    as.character(e2[[1]]$finalize %||% "(없음)"))
local({
  orig <- rc_close_finalize
  assign("rc_close_finalize", function(...) stop("주입 오류"), envir = globalenv())
  on.exit(assign("rc_close_finalize", orig, envir = globalenv()), add = TRUE)
  r <- tryCatch(rc_close(RD, note = "자체 시험", registry_path = REG, probes = c("탐침 하나", "탐침 둘")), error = function(e) e)
  e3 <- Filter(function(z) identical(z$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)
  chk("C7n 마감 훅 오류 → 닫기는 끝난다(등록부 complete · finalize = 'error: …' · 결과 원장 한 줄 그대로)",
      !inherits(r, "error") && identical(e3[[1]]$status, "complete") && startsWith(as.character(e3[[1]]$finalize %||% ""), "error: 주입 오류") &&
        length(rc_outcomes_read(OUTL)) == 1L, if (inherits(r, "error")) conditionMessage(r) else as.character(e3[[1]]$finalize %||% ""))
})
## 사전등록 최종 후보 읽기(p2 · p3) — verdict.json selected[[1]] 단위의 판정 칸(진단 · 기준 칸 제외) · 시행 집합 = 잰 칸 전부 · 스윕만 마감
local({
  FD <- file.path(SB, "fin"); RS <- file.path(FD, "results"); dir.create(RS, recursive = TRUE)
  SPF <- file.path(FD, "cell_spec.json"); writeLines('{"code":"E1_D1"}', SPF)
  cl <- list(list(code = "E1_D1", engine = "E1", component = "D1", role = "variant", spec = SPF),
             list(code = "E2_D1", engine = "E2", component = "D1", role = "variant", spec = SPF),
             list(code = "E1_D1x", engine = "E1", component = "D1", role = "diagnostic", spec = SPF),
             list(code = "E1_RX0", engine = "E1", component = "RX0", role = "reference", spec = SPF),
             list(code = "E1_D2", engine = "E1", component = "D2", role = "variant", spec = SPF),
             list(code = "E2_D2", engine = "E2", component = "D2", role = "variant", spec = SPF))
  for (c in cl) { a <- file.path(FD, "arts", c$code); dir.create(a, recursive = TRUE)
    writeLines(as.character(jsonlite::toJSON(list(strategy_id = paste0("S_", c$code), essence_grade = "A",
                                                  selection_type = if (identical(c$code, "E2_D1")) "chain" else "sweep"), auto_unbox = TRUE)),
               file.path(a, "authoritative_remeasure.json"))
    if (!identical(c$code, "E2_D2")) writeLines(as.character(jsonlite::toJSON(list(ok = TRUE, artifacts = a), auto_unbox = TRUE)), file.path(RS, paste0(c$code, ".json"))) }
  sp2 <- list(template = "p2_device", round_id = "P2R99_selftest", cells = cl); PP <- list(results = RS)
  calls <- list()
  fn <- function(candidate_dir, trial_dirs, strategy_id, spec_path, root, write) {
    calls[[length(calls) + 1L]] <<- list(cand = candidate_dir, n = length(trial_dirs), sid = strategy_id, spec = spec_path, write = write)
    list(status = "regrade ok(A→A) · gate publish") }
  f1 <- rc_close_finalize(sp2, list(selected = list(list(device = "D1")), verdict = "supported"), PP, write = FALSE, fn = fn)
  chk("C7o 최종 후보 = selected[[1]] 단위(D1)의 판정 칸 E1_D1 · E2_D1(진단 · 기준 칸 제외) · 스윕만 마감(E2_D1 chain = skip) · 시행 집합 = 잰 칸 5",
      length(calls) == 1L && identical(basename(calls[[1]]$cand), "E1_D1") && calls[[1]]$n == 5L && identical(calls[[1]]$sid, "S_E1_D1") &&
        identical(calls[[1]]$spec, SPF) && identical(calls[[1]]$write, FALSE) && grepl("E1_D1: regrade ok", f1$status) &&
        grepl("E2_D1: skip 스윕 아님(chain)", f1$status, fixed = TRUE) && !grepl("E1_D1x|E1_RX0", f1$status) && identical(f1$coarse, "done"), f1$status)
  f2 <- rc_close_finalize(sp2, list(selected = list(), verdict = "falsified"), PP, fn = fn)
  f3 <- rc_close_finalize(sp2, list(selected = list(list(device = "D2"))), PP, fn = fn)
  f4 <- rc_close_finalize(sp2, list(selected = list(list(device = "D1"))), PP, fn = function(...) stop("재채점 실패"))
  f5 <- rc_close_finalize(c(sp2[setdiff(names(sp2), "template")], list(template = "p3_construction")), list(selected = list(list(method = "D1"))), PP, fn = fn)
  chk("C7p 최종 후보 없음(판정 falsified) = skip · 측정 산출 없는 칸 = skip · 마감 오류 = 칸별 'error: …'(coarse error) · p3 는 method 단위",
      startsWith(f2$status, "skip: 최종 후보 없음") && identical(f2$coarse, "skip") && grepl("E2_D2: skip 측정 산출 없음", f3$status) &&
        grepl("E1_D1: error: 재채점 실패", f4$status) && identical(f4$coarse, "error") && grepl("최종 후보 D1", f5$status) && length(calls) == 3L,
      paste(f2$status, f3$status, f4$status, f5$status, sep = " || "))
})
rc_probe_consume(paste0(RID, "#1"), "NEXT_ROUND", OUTL)
chk("C7f 탐침 이어받기 — 열린 탐침 1개 남음 · 같은 탐침 재사용 거부 · 없는 탐침 거부",
    length(rc_open_probes(OUTL, "P1_RETURN")) == 1L && grepl("이미 이어받은", err_of(rc_probe_consume(paste0(RID, "#1"), "OTHER", OUTL))) &&
      grepl("원장에 없는 탐침", err_of(rc_probe_consume(paste0(RID, "#9"), "OTHER", OUTL))) && grepl("형식", err_of(rc_probe_consume("no_hash", "OTHER", OUTL))))
md <- rc_outcomes_md(OUTL, "P1_RETURN")
chk("C7g 다음 설계 입력(markdown) — 탐침 2줄(하나는 '이어받음') · 교훈 · 연속 '잡음 이내' 1회",
    sum(grepl("다음 탐침", md)) == 2L && sum(grepl("(이어받음)", md, fixed = TRUE)) == 1L && any(grepl("교훈: 교훈 하나", md)) &&
      identical(rc_r7_streak(OUTL, "P1_RETURN"), 1L))
## 양성 대조 — 날짜 검사 줄을 뺀 사본은 정보 경계 뒤 날짜가 든 글을 받아들인다(C7b 가 이것을 잡는다)
local({
  src <- readLines(file.path(RC_DIR, "outcomes.R"), warn = FALSE, encoding = "UTF-8")
  hit <- grep('if (length(leaks)) stop("[round_core close] 결과 원장 글에 정보 경계 뒤 날짜가 있다', src, fixed = TRUE)
  hit2 <- grep("if (!isTRUE(ci$ok)) stop(", src, fixed = TRUE)   # 11-10: 같은 날짜 규칙을 쓰는 처방 입력 검사(rc_input_issues)도 함께 뺀다
  mut <- src; if (length(hit) == 1L && length(hit2) == 1L) mut[c(hit, hit2)] <- ""
  e <- new.env(parent = globalenv()); eval(parse(text = mut, keep.source = FALSE), envir = e)
  s <- rc_spec_load(file.path(RD, "round_spec.json"), check_files = FALSE)
  r <- tryCatch(e$rc_outcome_record(s, rc_json_read(file.path(P$results, "verdict.json")), "2024-03-15 급락", probes = c("a", "b"), P = P), error = function(x) x)
  chk("C7h 날짜 검사를 뺀 사본은 경계 뒤 날짜를 통과시킨다 — C7b 가 실제로 잰다", length(hit) == 1L && !inherits(r, "error") && identical(r$note, "2024-03-15 급락"))
})
cat("x", file = P$prereg, append = TRUE)
chk("C8 판정 뒤 사전등록 변경 → 종료 기록 거부(R2)", grepl("R2", err_of(rc_close(RD, note = "재기록", registry_path = REG, probes = c("a", "b")))))

cat("D 캐시 키 · 핀 어휘\n")
AD <- file.path(SB, "art"); dir.create(AD)
for (f in RC_EVAL_KEY_FILES) writeLines(f, file.path(AD, f))
k0 <- rc_eval_key(AD, NULL, NULL, "2022-12-31", manifest_md5 = "m")
cat("1", file = file.path(AD, "04_holdings.csv"), append = TRUE)
chk("D1 칸 산출물이 바뀌면 캐시 키가 바뀐다(재측정 뒤 옛 평가 금지)", !identical(k0, rc_eval_key(AD, NULL, NULL, "2022-12-31", manifest_md5 = "m")))
chk("D2 τ_D · 코어 매니페스트 · 행동 카드 설정이 바뀌어도 바뀐다",
    !identical(rc_eval_key(AD, NULL, NULL, "2022-12-31", "m"), rc_eval_key(AD, NULL, NULL, "2021-12-31", "m")) &&
    !identical(rc_eval_key(AD, NULL, NULL, "2022-12-31", "m"), rc_eval_key(AD, NULL, NULL, "2022-12-31", "m2")) &&
    !identical(rc_eval_key(AD, NULL, NULL, "2022-12-31", "m"), rc_eval_key(AD, NULL, "b", "2022-12-31", "m")))
pins <- pre$pins
chk("D3 지금 핀 = 등록 핀(불일치 0)", !length(rc_pins_mismatches(pins)))
p2 <- pins; p2$overlay_arms <- list()
chk("D4 대조 함수 없는 핀 종류 = 불일치(통과 금지)", any(grepl("대조 함수가 없는", rc_pins_mismatches(p2))))
p3 <- pins; p3$core$manifest_md5 <- "0000"
chk("D5 코어 매니페스트가 다르면 불일치", any(grepl("코어 판", rc_pins_mismatches(p3))))
cat("E P1 표준 구성 · 라운드 골격\n")
IR <- file.path(SB, "init", "P1R98_init_selftest")
eng <- list(list(engine = "E2", engine_path = "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
                 paper = list(url = "https://arxiv.org/abs/2002.06975", paper_key = "2002.06975",
                              title = "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management"),
                 family_root = "2002.06975", n_family = 216L, n_trials_basis = "자체 시험"))
ok_init <- err_of(rc_init_p1(IR, "P1R98_init_selftest", eng, purpose = "자체 시험", hypothesis = "골격 생성"))
chk("E1 골격 생성 · 사양 검사 통과", identical(ok_init, "") && identical(err_of(rc_spec_load(file.path(IR, "round_spec.json"))), ""), ok_init)
gen <- rc_json_read(file.path(IR, "specs", "P1R98_E2_C0.json")); ref <- rc_json_read(RC_P1_LIKE)
same <- setdiff(names(ref), c("code", "label", "idea", "selection_accounting", "fixed_axes", "base_signal"))
chk("E2 표준 구성 = P0R01 C0 선례(엔진 · 논문 · 시행 회계 · 축 밖 필드 동일)",
    identical(gen[same], ref[same]) && identical(gen$fixed_axes[setdiff(names(ref$fixed_axes), "measurement_axis")], ref$fixed_axes[setdiff(names(ref$fixed_axes), "measurement_axis")]))
chk("E3 측정 축 = 활성 epoch(정본)", identical(gen$fixed_axes$measurement_axis,
    rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active")))
chk("E4 기존 사양 덮어쓰기 = 거부", grepl("덮어쓰지 않는다", err_of(rc_init_p1(IR, "P1R98_init_selftest", eng, "x", "y"))))
bad_like <- file.path(SB, "bad_like.json"); bl <- ref; bl$fixed_axes$n_max <- 30L; rc_json_write(bl, bad_like)
chk("E5 선례 고정 축 ≠ 정본 = 멈춤(정본 표류 탐지)", grepl("정본", err_of(rc_p1_cell_spec("X", eng[[1]]$engine_path, eng[[1]]$paper, "f", 1L, "b", like = bad_like))))
Sys.unsetenv("RC_SA_ROOT")
cat(sprintf("\n== round_core_v1_flow: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1_flow","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
