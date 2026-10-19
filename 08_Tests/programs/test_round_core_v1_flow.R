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
on.exit(unlink(SB, recursive = TRUE), add = TRUE)
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
rc_close(RD, note = "자체 시험", registry_path = REG)
e2 <- Filter(function(z) identical(z$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)
chk("C7 종료 기록 — complete · 판정 요약 · 해석 메모", identical(e2[[1]]$status, "complete") && grepl("^자격 2/3", e2[[1]]$verdict$label) &&
      identical(e2[[1]]$verdict$note, "자체 시험"))
cat("x", file = P$prereg, append = TRUE)
chk("C8 판정 뒤 사전등록 변경 → 종료 기록 거부(R2)", grepl("R2", err_of(rc_close(RD, note = "재기록", registry_path = REG))))

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
