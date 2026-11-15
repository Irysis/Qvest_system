## test_round_core_v5.R — round_core v5(2026-11-15 · v4 + 생성기 입력 수리) 시험. 고친 곳마다 양방향(양성 = 걸린다 · 음성 = 정상은 안 걸린다)만 둔다
##   (도훈 11-12 '테스트 좀 그만하자' — 그 밖의 시험 묶음은 만들지 않는다 · v4 의 나머지 동작은 Z 의 파일 대조가 v4 출시 시험 71/0 에 묶는다).
##   L 사유 코드 설명(설계 입력 §1) — L1 결함 재현(v4 방식 줄은 처방 입력 검사에 걸린다) · L2 v5 줄 통과 · 코드 전부 · 깨끗한 설명 원문 · 걸린 설명만 표식 ·
##     L3 따로는 지나고 이으면 걸리는 두 설명 → 코드만
##   U 사슬 목적 글(설계 입력 §0) — 가림 = id 안의 8자리 날짜만(변경분 점검 M-1 · 재점검 M-2): id 만 든 목적은 보인다 · 그 밖의 날짜 · 연도 꼴 열은 NULL(등록 거부) ·
##     등급 표기 · 시험 창 수치 NULL · 빈 목적 · 실제 P4C01 목적
##   S §0 두 줄(.rcp4_section0 · R-1) — 정책 줄도 검사(정규식 안의 τ_D 뒤 연도 = 거부) · 정상 정책 = 두 줄
##   P 걸음 정책 — 등록 검사(어휘 · 축 · 정규식 · 기저 엔진 · 근거) · 걸음 열기 검사(블록 · 바뀐 축(판단 C-20261115-074) · 부품 엔진 · 판독 불가)
##   C 등록 검사 통합 — 실제 P4C01 사슬 판(읽기만)에 v5 rc_p4_chain_check: 그대로 통과 · 정책 붙여 통과 · 잘못된 정책 · 보일 수 없는 목적 ·
##     정규식 안 연도 · 기저 칸 사양이 정책 밖(S-1)은 거부
##   R 사슬 판 만들기 왕복(R-2 (d)) — tempdir 에 rc_p4_chain_new(step_policy =) → 다시 읽기 → 검사 통과 · 잘못된 정책은 만들지 않는다
##   E 틱 경로(R-2 (b) · 판단 C-20261115-075 — 다음 판 시험이 이 묶음을 승계한다) — 실제 P4C01 상태 · 실제 기저 풀(읽기만)로 v5 설계 입력 · 생성기 작업 폴더(tempdir)
##   Z 판 무접촉 — v1 ~ v4 매니페스트 = RELEASES · v5 와 v4 의 파일 차이 = 여섯 파일(util · load · driver · measure_cell · standing · p4)
## 걸음 열기 진입점(rc_p4_step_open 의 정책 호출)의 양성 대조는 실제 P4C02 사슬에서 등록 · 기저 측정 뒤 한다(거부되는 열기는 원장에 아무것도 쓰지 않는다 · DESIGN_draft §4).
## 격리: 쓰기 = 임시 폴더(tempdir)뿐 · 실제 파일은 읽기만. 성과 값은 읽지도 출력하지도 않는다(설계 입력은 검사 결과 · 줄 머리만 본다).
## 실행: cd 04_Research/strategies && QM_ROOT=<저장소> Rscript <저장소>/08_Tests/programs/test_round_core_v5.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v5/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/rx_round.R"))))   # 도구 상자(rx_toolbox_md) — 생성기 작업 폴더
stopifnot(identical(RC_VERSION, "v5"))
assign("rc_perf_log", function(...) invisible(NULL), envir = globalenv())   # 실행 시간 기록을 저장소에 남기지 않는다
root <- rc_root(); tau <- as.Date(rc_ref_value("06_Registry/behavior_card.json::tau_d", root))
NP <- 0L; NF <- 0L
chk <- function(id, cond, note = "") {
  ok <- isTRUE(cond); if (ok) NP <<- NP + 1L else NF <<- NF + 1L
  cat(sprintf("[%s] %s%s\n", if (ok) "PASS" else "FAIL", id, if (nzchar(note)) paste0(" — ", note) else ""))
}
errs <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
clean <- function(x) isTRUE(rc_input_issues(list(x), tau)$ok)
T0RX <- "^04_Research/strategies/FC_(FAM_[a-z_]+|TOTAL_EW)/engine[.]R$"
BASE <- "04_Research/strategies/FC_FAM_value/engine.R"
C1D <- file.path(root, "04_Research/programs/P4_ASSEMBLY/P4C01_fc_blend")
SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_v5_test")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
REAL <- c(file.path(C1D, c("chain_spec.json", "chain_steps.jsonl", "base_cell_spec.json", "pool_snapshot.json")), file.path(root, "06_Registry/rx_generator.json"),
          file.path(root, "04_Research/programs/_lib/round_core/RELEASES.json"), file.path(root, "06_Registry/round_outcomes.jsonl"))
REAL0 <- vapply(REAL, function(p) if (file.exists(p)) rc_md5(p) else "absent", "")

## ── L 사유 코드 설명 ─────────────────────────────────────────────────────────
v4line <- paste0("- 사유 코드: ", paste(sprintf("`%s` = %s", names(RC_P4_REASONS), unname(RC_P4_REASONS)), collapse = " · "))
chk("L1 결함 재현 — v4 방식(설명 전부 이음) 줄은 처방 입력 검사에 걸린다", !clean(v4line))
lg <- suppressMessages(.rcp4_reason_legend(tau))
chk("L2a v5 줄은 처방 입력 검사를 지난다", clean(lg))
chk("L2b 코드 전부", all(vapply(names(RC_P4_REASONS), function(k) grepl(sprintf("`%s`", k), lg, fixed = TRUE), TRUE)))
chk("L2c 깨끗한 설명은 원문 그대로", grepl(sprintf("`no_engine` = %s", RC_P4_REASONS[["no_engine"]]), lg, fixed = TRUE))
nbad <- sum(!vapply(names(RC_P4_REASONS), function(k) clean(sprintf("`%s` = %s", k, RC_P4_REASONS[[k]])), TRUE))
chk("L2d 걸린 설명만 생략 표식", nbad >= 1L && lengths(regmatches(lg, gregexpr("설명 생략", lg, fixed = TRUE))) == nbad, sprintf("걸린 설명 %d", nbad))
R3 <- c(a_code = "전 기간 참고 문구", b_code = "판단 T4 리뷰")
chk("L3a 두 설명은 따로는 지난다", clean(sprintf("`a_code` = %s", R3[["a_code"]])) && clean(sprintf("`b_code` = %s", R3[["b_code"]])))
chk("L3b 이으면 걸린다(같은 문단 = 키워드 + 수치)", !clean(paste0("- 사유 코드: `a_code` = ", R3[["a_code"]], " · `b_code` = ", R3[["b_code"]])))
l3 <- suppressMessages(.rcp4_reason_legend(tau, R3))
chk("L3c 이은 줄이 걸리면 코드만 · 검사 통과", clean(l3) && grepl("설명 생략 — 처방 입력 검사 미통과): `a_code` · `b_code`", l3, fixed = TRUE))

## ── U 사슬 목적 글 ───────────────────────────────────────────────────────────
HEAD <- "- 목적(리뷰 · 결정 id 안의 날짜는 § 로 가림): "
p1 <- rc_json_read(file.path(C1D, "chain_spec.json"))$purpose
chk("U1a 실제 P4C01 목적 원문은 처방 입력 검사에 걸린다(리뷰 id 날짜)", !clean(p1))
u1 <- .rcp4_purpose_view(p1, tau)
chk("U1b 가림 뒤 줄 = 통과 · 머리말 · § 표식", !is.null(u1) && clean(u1) && startsWith(u1, HEAD) && grepl("§", u1, fixed = TRUE))
u2 <- .rcp4_purpose_view("판단 C-20261115-048 · 결정 LOWBETA-ENGINES-BASE-USE-20261113 · 철학 R-20261115-009 · 결정 FACTOR-SPINE-STAGE1-20261112 D4 를 따른다", tau)
chk("U2 id 만 든 목적 = 보인다 · id 날짜만 § (M-1)", !is.null(u2) && clean(u2) && !grepl("2026111[0-9]", u2) &&
      grepl("C-§-048", u2, fixed = TRUE) && grepl("USE-§", u2, fixed = TRUE) && grepl("R-§-009", u2, fixed = TRUE) && grepl("STAGE1-§", u2, fixed = TRUE))
FORMS <- c(range = "기저는 2023~2025 구간에서 S 1.2 · Calmar 0.9", year = "기저는 2024 에 S 1.2", fy = "기저는 FY2024 에 S 1.2", mon = "기저는 Mar 2023 이후 S 1.2",
           c8 = "기저는 20230315 부터 S 1.2", c6 = "기저는 202303 부터 S 1.2", half = "기저는 23H1 에 S 1.2", iso = "2023-05-01 이후 자료는 쓰지 않는다 · 결정 C-20261115-001",
           span8 = "기저는 20200101-20231231 구간 S 1.2", ver = "판 v2-20230101 이후 S 1.2")   # span8 · ver = 재점검 M-2(숫자 · 소문자 뒤 '-' 는 id 가 아니다)
for (nm in names(FORMS)) chk(sprintf("U3-%s τ_D 뒤 날짜 · 연도 꼴은 가리지 않는다 = NULL(등록 거부 · M-1)", nm), is.null(.rcp4_purpose_view(FORMS[[nm]], tau)))
chk("U4 등급 표기 = NULL", is.null(.rcp4_purpose_view("최종 후보가 등급 A 면 Judge 로 간다", tau)))
chk("U5 시험 창 수치 = NULL", is.null(.rcp4_purpose_view("시험 창 Calmar 1.5 를 넘는 칸만 고른다", tau)))
chk("U6 빈 목적 = '(목적 글 없음)' 줄", identical(.rcp4_purpose_view("", tau), paste0(HEAD, "(목적 글 없음)")))

## ── S §0 두 줄 ───────────────────────────────────────────────────────────────
okpol <- list(blocks = list("blend"), axes = list("base_signal"), part_engine_rx = T0RX, source = "시험")
s0 <- .rcp4_section0(list(purpose = "블렌드만 연다", step_policy = okpol), tau)
chk("S1 정상 정책 = 두 줄 · 둘 다 통과 · 정책 줄에 블록 · 축 · 정규식", isTRUE(s0$ok) && length(s0$lines) == 2L && all(vapply(s0$lines, clean, TRUE)) &&
      grepl("`blend`", s0$lines[2], fixed = TRUE) && grepl("`base_signal`", s0$lines[2], fixed = TRUE) && grepl(T0RX, s0$lines[2], fixed = TRUE))
RX24 <- "^04_Research/strategies/(FC_FAM_[a-z_]+|cohort/2024/[A-Z_]+)/engine[.]R$"
chk("S2 정규식 안 τ_D 뒤 연도 = §0 실을 수 없음(R-1)", !isTRUE(.rcp4_section0(list(purpose = "블렌드만", step_policy = modifyList(okpol, list(part_engine_rx = RX24))), tau)$ok))
chk("S3 정책 없음 = '없음' 줄 · 통과", isTRUE(.rcp4_section0(list(purpose = "블렌드만"), tau)$ok))

## ── P 걸음 정책 ──────────────────────────────────────────────────────────────
chk("P1 정책 없음 = 통과", !errs(.rcp4_step_policy_check(NULL, BASE)))
chk("P2 정상 정책(블록 · 축 · 정규식) = 통과", !errs(.rcp4_step_policy_check(okpol, BASE)))
chk("P3 어휘 밖 키 = 거부", errs(.rcp4_step_policy_check(c(okpol, list(extra = 1)), BASE)))
bp <- okpol; bp$blocks <- list("blend", "foo"); chk("P4 블록 어휘 밖 = 거부", errs(.rcp4_step_policy_check(bp, BASE)))
bp <- okpol; bp$blocks <- list(); chk("P5 빈 블록 목록 = 거부", errs(.rcp4_step_policy_check(bp, BASE)))
bp <- okpol; bp$axes <- list("base_signal", "foo"); chk("P6 축 어휘 밖 = 거부", errs(.rcp4_step_policy_check(bp, BASE)))
bp <- okpol; bp$axes <- list(); chk("P7 빈 축 목록 = 거부", errs(.rcp4_step_policy_check(bp, BASE)))
bp <- okpol; bp$blocks <- list("weighting"); chk("P7b 블록 · 축 짝 없음(weighting + base_signal) = 거부(재점검 S-7)", errs(.rcp4_step_policy_check(bp, BASE)))
bp <- okpol; bp$blocks <- list("blend", "weighting"); bp$axes <- list("base_signal", "weighting"); chk("P7c 짝 있음(blend · weighting) = 통과", !errs(.rcp4_step_policy_check(bp, BASE)))
chk("P8 정규식 오류 = 거부", errs(.rcp4_step_policy_check(modifyList(okpol, list(part_engine_rx = "(")), BASE)))
chk("P9 기저 엔진이 정규식 밖 = 거부", errs(.rcp4_step_policy_check(okpol, "04_Research/strategies/FC_FAM_value_ICW/engine.R")))
chk("P10 근거 문구 없음 = 거부", errs(.rcp4_step_policy_check(okpol[c("blocks", "axes", "part_engine_rx")], BASE)))
chk("P11 blocks · axes · 정규식 셋 다 없음 = 거부", errs(.rcp4_step_policy_check(list(source = "시험"), BASE)))
bcs <- rc_json_read(file.path(C1D, "base_cell_spec.json"))
mk <- function(nm, paths) { s <- bcs; s$base_signal <- if (is.null(paths)) list(kind = "factors") else list(kind = "engine_blend", paths = as.list(paths))
  f <- file.path(SB, paste0(nm, ".json")); rc_json_write(s, f); f }
fg <- "04_Research/strategies/FC_FAM_growth/engine.R"
f_ok <- mk("ok", c(BASE, fg)); f_icw <- mk("icw", c(BASE, "04_Research/strategies/FC_FAM_growth_ICW/engine.R"))
f_lane <- mk("lane", c(BASE, "04_Research/strategies/RP_AUTO_2002_06975/engine.R")); f_none <- mk("none", NULL)
W <- function(...) .rcp4_step_policy_why(okpol, ..., root = root)
chk("P12 blend · base_signal 축 · T0 부품 = 사유 없음", !length(W("blend", f_ok, changed = "base_signal")))
chk("P13 정책 밖 블록(weighting) = 사유", length(W("weighting", f_ok, changed = "base_signal")) == 1L)
chk("P14 정책 밖 축(blend 블록의 factors 축 블렌드) = 사유(판단 C-20261115-074)", any(grepl("칸 사양 축: factors", W("blend", f_ok, changed = "factors"), fixed = TRUE)))
chk("P15 정책 밖 축(base_weight) = 사유", any(grepl("base_weight", W("blend", f_ok, changed = c("base_signal", "base_weight")), fixed = TRUE)))
chk("P16 IC 가중 부품 = 사유", any(grepl("FC_FAM_growth_ICW", W("blend", f_icw, changed = "base_signal"), fixed = TRUE)))
chk("P17 레인 엔진 부품 = 사유", any(grepl("RP_AUTO_2002_06975", W("blend", f_lane, changed = "base_signal"), fixed = TRUE)))
chk("P18 기저 신호 경로를 읽지 못함 = 사유(fail-closed)", any(grepl("읽지 못했다", W("blend", f_none, changed = "base_signal"), fixed = TRUE)))
chk("P19 정책 없음 = 사유 없음(어떤 블록 · 축 · 부품이든)", !length(.rcp4_step_policy_why(NULL, "weighting", f_lane, root, changed = "factors")))
chk("P20 칸 사양 파일 없음 · 축 모름 = 블록 검사만", identical(W("blend", NA_character_), character(0)) && length(W("universe", file.path(SB, "missing.json"))) == 1L)

## ── C 등록 검사 통합(실제 사슬 판 · 읽기만) ───────────────────────────────────
s1 <- rc_json_read(file.path(C1D, "chain_spec.json"))
chk("C1 실제 P4C01 사슬 판 = v5 등록 검사 통과(정책 없음)", !errs(rc_p4_chain_check(s1, root)))
s2 <- s1; s2$step_policy <- okpol; chk("C2 걸음 정책 붙임 = 통과", !errs(rc_p4_chain_check(s2, root)))
s3 <- s1; s3$step_policy <- okpol; s3$step_policy$blocks <- list("foo"); chk("C3 잘못된 정책 = 거부", errs(rc_p4_chain_check(s3, root)))
s4 <- s1; s4$purpose <- paste(s1$purpose, "시험 창 Calmar 1.5 를 넘는 칸만 고른다."); chk("C4 보일 수 없는 목적 = 거부", errs(rc_p4_chain_check(s4, root)))
s5 <- s1; s5$step_policy <- modifyList(okpol, list(part_engine_rx = RX24)); chk("C5 기저와 맞지만 τ_D 뒤 연도를 품은 정규식 = 거부(R-1)", errs(rc_p4_chain_check(s5, root)))
s6 <- s1; s6$base$engine_path <- fg; s6$step_policy <- modifyList(okpol, list(part_engine_rx = "^04_Research/strategies/FC_FAM_growth/engine[.]R$"))
chk("C6 기저 칸 사양의 기저 신호가 정책 밖 = 거부(S-1)", errs(rc_p4_chain_check(s6, root)))

## ── R 사슬 판 만들기 왕복(tempdir) ────────────────────────────────────────────
POOLR <- rc_p4_base_pool(root)
RD <- file.path(SB, "chain_rt"); bcp <- "04_Research/programs/P4_ASSEMBLY/P4C01_fc_blend/base_cell_spec.json"
rt <- tryCatch(rc_p4_chain_new(RD, "P4C93_v5rt", s1$base$key, POOLR, base_cell_spec = bcp, adoption_rules = s1$adoption$rules, budget = s1$budget,
                               purpose = "왕복 시험 — 블렌드만 연다", root = root, step_policy = okpol), error = function(e) e)
sr <- if (!inherits(rt, "error")) rc_json_read(rt) else list()
chk("R1 정책 있는 사슬 판 = 만들어진다 · 다시 읽은 정책 = 같은 값 · 검사 통과", !inherits(rt, "error") && identical(unlist(sr$step_policy$blocks), "blend") &&
      identical(unlist(sr$step_policy$axes), "base_signal") && identical(sr$step_policy$part_engine_rx, T0RX) && !errs(rc_p4_chain_check(sr, root)),
    if (inherits(rt, "error")) substr(conditionMessage(rt), 1, 160) else "")
RD2 <- file.path(SB, "chain_rt2"); bp <- okpol; bp$axes <- list("foo")
chk("R2 잘못된 정책 = 만들지 않는다(사슬 판 없음)", errs(rc_p4_chain_new(RD2, "P4C92_v5rt", s1$base$key, POOLR, base_cell_spec = bcp, adoption_rules = s1$adoption$rules,
                                                                 budget = s1$budget, purpose = "왕복 시험", root = root, step_policy = bp)) && !file.exists(file.path(RD2, "chain_spec.json")))

## ── E 틱 경로(실제 상태 · 실제 기저 풀 · 읽기만 · 다음 판 승계) ───────────────
di <- tryCatch(suppressMessages(rc_p4_design_input(root, C1D, pool = POOLR)), error = function(e) paste("ERR:", conditionMessage(e)))
chk("E1 실제 P4C01 설계 입력 = 만들어진다 · 전수 검사 통과", !startsWith(di[1], "ERR:") && clean(di), if (startsWith(di[1], "ERR:")) substr(di, 1, 160) else "")
chk("E2 §0 목적 줄 · 정책 줄(정책 없음)", grepl("## 0. 사슬 목적", di, fixed = TRUE) && grepl(paste0("\n", HEAD), di, fixed = TRUE) &&
      grepl("걸음 정책(기계 검사 — 밖이면 걸음 열기 거부): 없음", di, fixed = TRUE))
WD <- file.path(SB, "wd")
wd <- tryCatch(suppressMessages(rc_p4_generator_workdir(C1D, WD, root, pool = POOLR)), error = function(e) e)
chk("E3 생성기 작업 폴더(무인 틱의 실제 단계 — v4 에서 멈춘 곳) = 네 파일", !inherits(wd, "error") &&
      setequal(basename(wd), c("design_input.md", "investment_philosophy_charter.md", "toolbox.md", "parent_cell_spec.json")) && all(file.exists(wd)),
    if (inherits(wd, "error")) substr(conditionMessage(wd), 1, 160) else "")

## ── Z 판 무접촉 ──────────────────────────────────────────────────────────────
rel <- rc_json_read(file.path(root, "04_Research/programs/_lib/round_core/RELEASES.json"))$releases
for (v in c("v1", "v2", "v3", "v4")) {
  r <- Filter(function(x) identical(x$version, v), rel)[[1]]
  chk(sprintf("Z1 %s 매니페스트 = RELEASES", v), identical(rc_core_manifest(file.path(root, "04_Research/programs/_lib/round_core", v))$manifest_md5, r$manifest_md5))
}
d4 <- file.path(root, "04_Research/programs/_lib/round_core/v4"); d5 <- file.path(root, "04_Research/programs/_lib/round_core/v5")
f4 <- sort(list.files(d4, pattern = "[.](R|sh)$")); f5 <- sort(list.files(d5, pattern = "[.](R|sh)$"))
dif <- f5[vapply(f5, function(f) !(f %in% f4) || !identical(rc_md5(file.path(d4, f)), rc_md5(file.path(d5, f))), TRUE)]
chk("Z2 같은 파일 목록 · 다른 파일 = 여섯", identical(f4, f5) && setequal(dif, c("util.R", "load.R", "driver.R", "measure_cell.R", "standing.R", "p4.R")), paste(dif, collapse = ","))
REAL1 <- vapply(REAL, function(p) if (file.exists(p)) rc_md5(p) else "absent", "")
chk("Z3 실제 파일 무접촉(P4C01 사슬 · 생성기 등록부 · RELEASES · 결과 원장)", identical(REAL0, REAL1), paste(basename(REAL)[REAL0 != REAL1], collapse = ","))
unlink(SB, recursive = TRUE)
cat(sprintf("\n== test_round_core_v5: %d 통과 · %d 실패 ==\n", NP, NF))
quit(status = if (NF) 1L else 0L)
