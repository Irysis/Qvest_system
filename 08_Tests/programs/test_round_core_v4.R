## test_round_core_v4.R — round_core v4(2026-11-13 · 자체 사양 입구 · 판 3 준비) 격리 시험. 새 관문마다 양방향(양성 = 걸린다 · 음성 = 정상은 안 걸린다)만 둔다
##   (도훈 11-12 '테스트 좀 그만하자' — 그 밖의 시험 묶음은 만들지 않는다).
##   V 보는 창 파일 누출 수리(test_hold) — v4 쓰기 · v3 쓰기(결함 재현 = 음성 대조 · 자식 프로세스)
##   F 데이터 지문 — 결합용 뷰가 v4 지문에 든다(가짜 루트 · 뷰가 바뀌면 지문이 갈린다 · v3 지문은 그대로)
##   T 입구 갈래(track) — 옛 판 받기 정지 = 같은 갈래의 더 높은 판만(v4) · v3 코어(자식)는 자체 사양 판 1 에 막히지 않고 레인 판 3 에는 막힌다
##   O 자체 사양 입구 — 실제 FC_* 30개(읽기만) · 임시 사본 돌연변이 · 사양 검사 · enqueue 시행 수 · 레인 갈래 스캔 = v3(실제 RP_AUTO_* 드라이런)
##   W orientation_layer 허용 조건 실증 — FC_TOTAL_ICW 사본 가중 줄 돌연변이: 짧은 창 실행이 '가중 단정 위반'으로 멈춘다 · 원본은 멈추지 않는다 ·
##     같은 돌연변이 사본은 스캔에서 own_generator_mismatch
##   Q 자격 통과 표 — 두 갈래에 걸친 같은 칸 = 모든 갈래 최신 판정 통과일 때만(v3 = 판 번호 큰 쪽 · 자식 대조) · 열 추가
##   P 기저 풀 — philosophy_unread · philosophy_hold(두 갈래: 상설 pass 기록 · 원천 라운드 영수증) · lowrisk_confirm_pending(엔진 단위 release_decision) ·
##     영수증 쓰기 도우미 거부 · 레인 행 판정 = v3(자식 대조)
##   C 사슬 — 원천 시행 빠지면 등록 거부 · 다 있으면 chain_registered.source_trials · N5 β 비대칭 blend 걸음(양방향) · 닫기 시행 집합 · 기대 수(가짜 재채점)
##   Z 실제 파일 무접촉
## 격리: 임시 폴더(SB)만 쓴다 — RC_SA_ROOT · 임시 등록부(실제 등록부 사본 · 합성 등록부) · 임시 판단 원장 · 임시 결정 기록부 · 임시 생성기 등록부(RC_RXG_PATH) ·
##   가짜 러너 · 가짜 재채점 · 엔진 실행은 저장소 밖 사본(진단 폴더도 임시). 성과 값은 읽지도 출력하지도 않는다(입구 · 풀 · 사슬 규칙은 폴더 실재만 본다).
## 실행: cd 04_Research/strategies && R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript <저장소>/08_Tests/programs/test_round_core_v4.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v4/standing.R"))) stop("저장소 루트가 아니다(v4 없음): ", ROOT)
T00 <- Sys.time(); PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
has_reason <- function(C, d, r) { x <- C[C$dir == d]$reasons; length(x) == 1L && r %in% strsplit(x, ";", fixed = TRUE)[[1]] }
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
assign("rc_perf_log", function(...) invisible(NULL), envir = globalenv())   # 실행 시간 기록(.cache/round_core/perf)을 저장소에 남기지 않는다(시험 대상 아님)
md5 <- function(p) if (file.exists(p)) unname(as.character(tools::md5sum(p))) else "absent"
CR <- file.path(ROOT, "04_Research/programs/_lib/round_core"); TAU <- "2022-12-31"
SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_v4")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
SAR <- file.path(SB, "sa"); Sys.setenv(RC_SA_ROOT = SAR)
GEN_REG <- file.path(SB, "rx_generator.json"); Sys.setenv(RC_RXG_PATH = GEN_REG)
## 격리 단정(~/.Renviron 의 QM_ROOT 덮어쓰기 · 임시 폴더 위치 · 적재 판) — 하나라도 어긋나면 아무것도 하지 않고 멈춘다
iso_ok <- identical(gsub("\\\\", "/", rc_root()), ROOT) && !startsWith(tolower(SB), tolower(paste0(ROOT, "/"))) &&
  identical(Sys.getenv("RC_SA_ROOT"), SAR) && identical(RC_VERSION, "v4") && grepl("/round_core/v4$", RC_DIR)
chk("A0 격리 — rc_root = 저장소 · 임시 폴더는 저장소 밖 · RC_SA_ROOT · RC_RXG_PATH = 임시 · 적재 판 = v4(RC_DIR v4)", iso_ok, c(rc_root(), SB, RC_DIR))
if (!iso_ok) { cat(sprintf("\n== test_round_core_v4: %d ok · %d FAIL ==\n", PASS, FAIL)); quit(status = 1L) }
## 실제 파일 전후 md5(Z1) — 판단 원장 · 결정 기록부는 다른 세션이 실시간으로 쓴다(md5 대조 불가 → Z2 가 이 시험의 표식이 없음을 본다)
SHARED <- c("06_Registry/q_judgment_ledger.json", "06_Registry/decision_register.json")
REAL <- c("06_Registry/research_programs.json", "06_Registry/factor_db_vintage.json", "06_Registry/round_outcomes.jsonl", "06_Registry/rx_generator.json",
          "04_Research/programs/_lib/round_core/RELEASES.json",
          "stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/standing_ledger.jsonl",
          "stage_artifacts/programs/P1_RETURN/P1S02_standing_qualification/standing_ledger.jsonl",
          "stage_artifacts/programs/P1_RETURN/P1R03_factor_family_composites/prereg.json",
          file.path("04_Research/strategies", c("FC_TOTAL_ICW", "FC_FAM_value", "FC_FAM_value_ICW"), "engine.R"),
          file.path("04_Research/strategies", c("FC_TOTAL_ICW", "FC_FAM_value", "FC_FAM_value_ICW"), "own_spec.json"),
          file.path("04_Research/strategies", c("FC_TOTAL_ICW", "FC_FAM_value", "FC_FAM_value_ICW"), "fce_diag.csv"), ".cache/gpu_lease.json")
REAL0 <- vapply(REAL, md5, ""); names(REAL0) <- REAL

## 자식 프로세스 — 판 ver 의 코어를 적재하고 식을 평가해 .res 를 돌려준다(한 프로세스 = 판 하나 · v2 · v3 시험과 같은 방식 · 환경은 물려받는다)
run_core <- function(ver, lines, tag) {
  f <- file.path(SB, paste0("child_", tag, ".R")); o <- file.path(SB, paste0("child_", tag, ".rds"))
  writeLines(c(sprintf('setwd("%s"); suppressMessages(source("04_Research/programs/_lib/round_core/%s/load.R"))', ROOT, ver),
               sprintf('stopifnot(identical(RC_VERSION, "%s"), identical(rc_root(), "%s")); suppressPackageStartupMessages(library(data.table))', ver, ROOT),
               lines, sprintf('saveRDS(.res, "%s")', o)), f, useBytes = TRUE)
  out <- suppressWarnings(system2("Rscript", shQuote(f), stdout = TRUE, stderr = TRUE))
  if (!file.exists(o)) { cat(tail(out, 15), sep = "\n"); stop("자식 프로세스 실패: ", tag) }
  readRDS(o)
}

## ═══ A. 출시 판 불변 ═══════════════════════════════════════════════════════════════
REL <- rc_json_read(file.path(CR, "RELEASES.json"))
for (v in c("v1", "v2", "v3")) {
  R0 <- Filter(function(r) identical(r$version, v), REL$releases)[[1]]; m <- rc_core_manifest(file.path(CR, v))
  chk(sprintf("A1 %s 디렉터리 매니페스트 = RELEASES %s(%s) — 출시 판 무수정", v, v, substr(R0$manifest_md5, 1, 8)),
      identical(m$manifest_md5, R0$manifest_md5) && all(vapply(names(R0$files), function(f) identical(m$files[[f]], R0$files[[f]]), TRUE)), m$manifest_md5)
}
M4 <- rc_core_manifest()
v4txt <- unlist(lapply(names(M4$files), function(f) readLines(file.path(RC_DIR, f), encoding = "UTF-8", warn = FALSE)))
chk("A2 v4 — 판 표기 v4 · 파일 20개(v3 와 같은 목록) · 매니페스트 ≠ v3 · 파일 안에 round_core/v1 · v2 · v3 고정 경로 0 · RELEASES 에 v4 항목 없음(출시 전)",
    identical(M4$version, "v4") && setequal(names(M4$files), names(rc_core_manifest(file.path(CR, "v3"))$files)) && length(M4$files) == 20L &&
      !identical(M4$manifest_md5, rc_core_manifest(file.path(CR, "v3"))$manifest_md5) && !any(grepl("round_core/v[123]", v4txt)) &&
      !any(vapply(REL$releases, function(r) identical(r$version, "v4"), TRUE)))

## ═══ V. 보는 창 파일 누출 수리(⑤ · test_hold) ═════════════════════════════════════════
cat("V 보는 창 파일\n")
TPL <- .rcs_p1_template_rules(ROOT)
mk_vis_round <- function(rid) {
  rd <- file.path(SB, "vis", rid); src <- file.path(rd, "shared"); dir.create(src, recursive = TRUE, showWarnings = FALSE)
  rc_json_write(list(schema = RC_SPEC_SCHEMA, program = "P1_RETURN", round_id = rid, template = "p1_qualification", core_version = "v4", tau_d = TAU,
                     purpose = "보는 창 파일 시험", hypothesis = "보는 창 파일 시험",
                     cells = list(list(code = "VA", engine = "EA", role = "variant", source_results = src), list(code = "VB", engine = "EB", role = "variant", source_results = src)),
                     rules = TPL, selection = list(rule = "none"), exposures = list()), file.path(rd, "round_spec.json"))
  rd
}
## 판정 경로 그대로(rc_evaluate → rc_p1_evaluate → rc_rules_apply → 보는 창 쓰기) · 등록 확인 · 핀 · 칸 평가 · 판정 표 원료만 대체(합성 표 · 실측 아님)
VIS_LINES <- function(rd) c(
  'assign("rc_registered", function(spec, P, root = rc_root(), registry_path = NULL) list(pins = list(), rules_resolved = rc_rules_resolve(spec[["rules"]], root)), envir = globalenv())',
  'assign("rc_pins_mismatches", function(pins, root = rc_root()) character(0), envir = globalenv())',
  'assign("rc_eval_env", function(root = rc_root(), bcfg_path = NULL) new.env(), envir = globalenv())',
  'assign("rc_perf_log", function(...) invisible(NULL), envir = globalenv())',
  paste0('assign("rc_p1_table", function(spec, root = rc_root()) data.table(engine = c("EA", "EB"), code = c("VA", "VB"), status = "evaluated", t_alpha_vis = c(3.1, 2.6), ',
         'alpha_ann_vis = c(0.05, 0.04), beta_vis = 0.9, port_t_vis = c(3.0, 2.7), n_vis = 200, uc_vis = c(0.70, 0.62), cagr_vis = 0.12, t_alpha_test = c(1.5, -0.5), ',
         'alpha_ann_test = c(0.03, -0.01), n_test = 40, uc_test = c(0.60, 0.50)), envir = globalenv())'),
  sprintf('rd <- "%s"; invisible(capture.output(rc_evaluate(rd, rc_root())))', rd),
  'vis <- jsonlite::fromJSON(file.path(rd, "results", "evaluation_visible.json"), simplifyVector = FALSE)',
  'ful <- jsonlite::fromJSON(file.path(rd, "results", "verdict.json"), simplifyVector = FALSE)',
  '.res <- list(vis = unique(unlist(lapply(vis$table, names))), full = unique(unlist(lapply(ful$table, names))), q = vapply(vis$table, function(r) isTRUE(r$qualify), TRUE))')
v4v <- run_core("v4", VIS_LINES(mk_vis_round("P1R94_v4vis")), "vis_v4")
v3v <- run_core("v3", VIS_LINES(mk_vis_round("P1R93_v3vis")), "vis_v3")
chk("V1 v4 쓰기(실제 rc_evaluate · 자식) — 보는 창 파일에 test_hold · *_test 열 없음 · 보는 창 규칙 열(qualify) · 보는 창 지표 남음 · 사람 쪽 verdict.json 은 test_hold · *_test 그대로",
    !("test_hold" %in% v4v$vis) && !any(grepl("_test$", v4v$vis)) && all(c("qualify", "t_alpha_vis", "uc_vis") %in% v4v$vis) && length(v4v$q) == 2L && all(v4v$q) &&
      all(c("test_hold", "alpha_ann_test") %in% v4v$full), paste(v4v$vis, collapse = ","))
chk("V2 대조 · v3 쓰기(같은 입력 · 자식) — test_hold 가 보는 창 파일에 남는다(결함 재현 = 음성 대조) · *_test 열은 v3 도 뺀다",
    "test_hold" %in% v3v$vis && !any(grepl("_test$", v3v$vis)), paste(v3v$vis, collapse = ","))
NEST <- list(list(id = "qq", type = "all_of", label = "q", of = list(list(id = "qa", type = "threshold", label = "a", metric = "x_test", op = ">", value = 0, basis = "시험"),
                                                                   list(id = "qb", type = "threshold", label = "b", metric = "y_vis", op = ">", value = 0, basis = "시험"))),
             list(id = "qc", type = "threshold", label = "c", metric = "z_vis", op = ">", value = 0, basis = "시험"))
chk("V3 rc_rules_test_ids — P1 템플릿 = test_hold 만 · 중첩(all_of 안 *_test) = 하위 id + 상위 id · 보는 창 지표 규칙만 = 없음(음성)",
    identical(rc_rules_test_ids(TPL), "test_hold") && setequal(rc_rules_test_ids(NEST), c("qa", "qq")) && !length(rc_rules_test_ids(NEST[2])))

## ═══ F. 데이터 지문 — 결합용 뷰(.cache/factor_combinable)가 칸 지문에 든다(③ · 가짜 루트 · 실제 .cache 무접촉) ═══════════════
cat("F 데이터 지문\n")
FR <- file.path(SB, "fproot"); FCV <- file.path(FR, ".cache", "factor_combinable"); dir.create(FCV, recursive = TRUE)
writeBin(as.raw(1:10), file.path(FCV, "fc_200001.parquet"))
fpr <- function(ver) { old <- Sys.getenv("QM_ROOT_POSIX", unset = NA); Sys.setenv(QM_ROOT_POSIX = FR)
  on.exit(if (is.na(old)) Sys.unsetenv("QM_ROOT_POSIX") else Sys.setenv(QM_ROOT_POSIX = old), add = TRUE)
  paste(suppressWarnings(system2(qv_bash(), c(shQuote(file.path(CR, ver, "fingerprint.sh")), "equality"), stdout = TRUE, stderr = FALSE)), collapse = "\n") }
fa4 <- fpr("v4"); fa3 <- fpr("v3"); writeBin(as.raw(1:20), file.path(FCV, "fc_200002.parquet")); fb4 <- fpr("v4"); fb3 <- fpr("v3")
chk("F1 결합용 뷰 — v4 지문에 '.cache/factor_combinable/' 줄(파일 수 · 크기 · 최신 mtime) · 뷰 파일이 늘면 v4 지문이 달라진다 · v3 지문은 그대로(뷰 미포함 = 음성 대조)",
    grepl(".cache/factor_combinable/ files=1 bytes=10 ", fa4, fixed = TRUE) && grepl(".cache/factor_combinable/ files=2 bytes=30 ", fb4, fixed = TRUE) &&
      !identical(fa4, fb4) && identical(fa3, fb3) && !grepl("factor_combinable", fa3, fixed = TRUE), c(fa4, "|", fb4))

## ═══ T. 입구 갈래(track) ══════════════════════════════════════════════════════════
cat("T 입구 갈래\n")
REG0 <- rc_json_read("06_Registry/research_programs.json")
REGT <- file.path(SB, "reg_track.json"); rc_json_write(REG0, REGT)
LED <- file.path(SB, "q_judgment_ledger_t.json"); RVR <- file.path(SB, "rv")
rv_file <- function(f) { dir.create(dirname(file.path(RVR, f)), recursive = TRUE, showWarnings = FALSE); writeLines("시험 리뷰", file.path(RVR, f)); f }
rvw <- function(id, role, trigger, round, file, challenges = list()) list(id = id, at = "x", role = role, trigger = trigger, scope = list(), file = rv_file(file),
                                                                          round = round, challenges = challenges)
p1f <- function(rid) sprintf("04_Research/programs/_supervision/superfan/philosophy/20261113_0900_P1_%s.md", rc_round_tag(rid))
rc_json_write(list(schema = "q_judgment_ledger_v1", judgments = list(), challenges = list(),
                   reviews = lapply(c("P1S91_v4own", "P1S92_v4lane", "P1S93_v3lane"), function(r) rvw(paste0("R-P1-", rc_round_tag(r)), "philosophy", "P1", r, p1f(r)))), LED)
review <- function(rd, v) { f <- file.path(SB, sprintf("review_%s_v%d.md", basename(rd), v)); writeLines("점검 ok", f); rc_mark_reviewed(rd, v, f, "ok") }
SEEDS <- list(list(code = "P0R01_E2_C0", engine = "E2", role = "reference", source_results = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results"))
LANE_O <- file.path(SB, "lane_own"); LANE_L <- file.path(SB, "lane_lane"); dir.create(LANE_L, recursive = TRUE)
cp_fc <- function(src, dst_root, nm = src) { d <- file.path(dst_root, nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  for (f in c("engine.R", "own_spec.json")) if (!isTRUE(file.copy(file.path(ROOT, "04_Research/strategies", src, f), file.path(d, f), overwrite = TRUE))) stop("복사 실패: ", src, "/", f)
  d }
invisible(cp_fc("FC_FAM_value", LANE_O)); invisible(cp_fc("FC_FAM_value_ICW", LANE_O))
reg_ed <- function(rd, rid, ed, scan) {
  rc_init_standing_p1(rd, rid, SEEDS, purpose = "코어 v4 자체 시험(격리)", hypothesis = "입구 갈래 · 자체 사양 입구", edition = ed, scan = scan,
                      exposures = list("시험"), conclusion_scope = list("자체 시험"), bcfg = NULL)
  rc_draft(rd); review(rd, 1L)
  rc_register(rd, registry_path = REGT, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR)
}
RD_OWN <- file.path(SB, "round", "P1S91_v4own"); RD_LANE <- file.path(SB, "round", "P1S92_v4lane")
g1 <- tryCatch(reg_ed(RD_OWN, "P1S91_v4own", 1L, list(source = "own_spec", lane_root = LANE_O)), error = function(e) e)
g2 <- tryCatch(reg_ed(RD_LANE, "P1S92_v4lane", 2L, list(lane_root = LANE_L)), error = function(e) e)
SO <- tryCatch(rc_json_read(file.path(RD_OWN, "round_spec.json")), error = function(e) list()); SL <- tryCatch(rc_json_read(file.path(RD_LANE, "round_spec.json")), error = function(e) list())
chk("T0 등록(임시 등록부 · v4) — 자체 사양 입구 판 1(track own_spec · 생성기 2 · 방향 층 engine_native + orientation_layer) · 레인 입구 판 2(track lane)",
    !inherits(g1, "error") && !inherits(g2, "error") && identical(SO$standing_cfg$track, "own_spec") && identical(SO$standing_cfg$scan$source, "own_spec") &&
      length(SO$standing_cfg$scan$generators) == 2L && identical(SL$standing_cfg$track, "lane") && identical(as.integer(SO$standing_cfg$edition), 1L),
    c(if (inherits(g1, "error")) conditionMessage(g1), if (inherits(g2, "error")) conditionMessage(g2)))
fake_ed <- function(reg_in, reg_out, rid, ed, track = NULL) {
  R <- rc_json_read(reg_in); i <- which(vapply(R$programs, function(p) p$id, "") == "P1_RETURN")
  rel <- file.path("stage_artifacts/programs/P1_RETURN", rid, "prereg.json"); f <- file.path(SAR, rel); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  cfg <- list(edition = ed, program = "P1_RETURN"); if (!is.null(track)) cfg$track <- track
  if (!file.exists(f)) rc_json_write(list(round_id = rid, spec = list(standing = TRUE, standing_cfg = cfg)), f)
  R$programs[[i]]$rounds <- c(R$programs[[i]]$rounds, list(list(round_id = rid, prereg = rel, prereg_md5 = md5(f), status = "registered")))
  rc_json_write(R, reg_out); reg_out
}
REG_L3 <- fake_ed(REGT, file.path(SB, "reg_l3.json"), "P1S94_fakelane", 3L)
REG_O2 <- fake_ed(REGT, file.path(SB, "reg_o2.json"), "P1S95_fakeown", 2L, "own_spec")
ctx_of <- function(rd, reg) tryCatch(rc_standing_context(rd, registry_path = reg, mode = "enqueue"), error = function(e) e)
c1o <- ctx_of(RD_OWN, REGT); c1l <- ctx_of(RD_LANE, REGT)
chk("T1 같은 갈래에 더 높은 판 없음 — 자체 사양 판 1 은 레인 판 2(번호 더 큼 · 다른 갈래)에 막히지 않는다 · 레인 판 2 도 열린다 · 맥락 track",
    !inherits(c1o, "error") && !inherits(c1l, "error") && identical(c1o$track, "own_spec") && identical(c1l$track, "lane"),
    c(if (inherits(c1o, "error")) conditionMessage(c1o), if (inherits(c1l, "error")) conditionMessage(c1l)))
c2l <- ctx_of(RD_LANE, REG_L3); c2o <- ctx_of(RD_OWN, REG_L3)
chk("T2 레인 판 3(같은 갈래 · 갈래 표식 없는 옛 판 = lane)이 등록되면 레인 판 2 는 새 항목을 받지 않는다 · 자체 사양 판 1 은 그대로(음성)",
    inherits(c2l, "error") && grepl("같은 입구 갈래(lane)", conditionMessage(c2l), fixed = TRUE) && !inherits(c2o, "error"), if (inherits(c2l, "error")) conditionMessage(c2l) else "막히지 않았다")
c3o <- ctx_of(RD_OWN, REG_O2); c3l <- ctx_of(RD_LANE, REG_O2)
chk("T3 자체 사양 판 2(같은 갈래)가 등록되면 자체 사양 판 1 이 막힌다 · 레인 판 2 는 그대로(음성)",
    inherits(c3o, "error") && grepl("같은 입구 갈래(own_spec)", conditionMessage(c3o), fixed = TRUE) && !inherits(c3l, "error"), if (inherits(c3o, "error")) conditionMessage(c3o) else "막히지 않았다")
E_T <- rc_standing_editions("P1_RETURN", registry_path = REG_L3)
chk("T3b rc_standing_editions track 열 — 자체 사양 판 = own_spec · 표식 없는 옛 판 · 레인 판 = lane",
    identical(E_T[round_id == "P1S91_v4own"]$track, "own_spec") && identical(E_T[round_id == "P1S94_fakelane"]$track, "lane") && identical(E_T[round_id == "P1S92_v4lane"]$track, "lane"))
REG3 <- file.path(SB, "reg_v3.json"); invisible(file.copy(REGT, REG3)); RD3 <- file.path(SB, "round", "P1S93_v3lane")
L3F <- file.path(SAR, "stage_artifacts/programs/P1_RETURN/P1S94_fakelane/prereg.json")
r3 <- run_core("v3", c(
  sprintf('REG3 <- "%s"; RD3 <- "%s"; LED <- "%s"; RVR <- "%s"; SB <- "%s"; LANE_L <- "%s"', REG3, RD3, LED, RVR, SB, LANE_L),
  'SEEDS <- list(list(code = "P0R01_E2_C0", engine = "E2", role = "reference", source_results = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results"))',
  'rc_init_standing_p1(RD3, "P1S93_v3lane", SEEDS, purpose = "코어 v3 대조(격리)", hypothesis = "갈래 모름", edition = 2L, scan = list(lane_root = LANE_L), exposures = list("시험"), conclusion_scope = list("자체 시험"), bcfg = NULL)',
  'rc_draft(RD3); f <- file.path(SB, "review_v3.md"); writeLines("점검 ok", f); rc_mark_reviewed(RD3, 1L, f, "ok")',
  'rg <- tryCatch({ rc_register(RD3, registry_path = REG3, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR); "" }, error = function(e) conditionMessage(e))',
  'a <- tryCatch({ rc_standing_context(RD3, registry_path = REG3, mode = "enqueue"); "" }, error = function(e) conditionMessage(e))',
  sprintf('R <- rc_json_read(REG3); i <- which(vapply(R$programs, function(p) p$id, "") == "P1_RETURN"); R$programs[[i]]$rounds <- c(R$programs[[i]]$rounds, list(list(round_id = "P1S94_fakelane", prereg = "stage_artifacts/programs/P1_RETURN/P1S94_fakelane/prereg.json", prereg_md5 = "%s", status = "registered"))); REG3b <- file.path(SB, "reg_v3b.json"); rc_json_write(R, REG3b)', md5(L3F)),
  'b <- tryCatch({ rc_standing_context(RD3, registry_path = REG3b, mode = "enqueue"); "" }, error = function(e) conditionMessage(e))',
  'E <- rc_standing_editions("P1_RETURN", registry_path = REG3)',
  '.res <- list(reg = rg, a = a, b = b, eds = as.data.frame(E))'), "track_v3")
chk("T4 v3 코어(자식 · 갈래 모름) — 자체 사양 판 1(edition 1)이 등록된 등록부에서 v3 레인 판 2 의 enqueue 맥락이 열린다(1 < 2) · 레인 판 3 을 더하면 막힌다(양방향)",
    identical(r3$reg, "") && identical(r3$a, "") && grepl("더 높은 판", r3$b) && "P1S91_v4own" %in% r3$eds$round_id && !("track" %in% names(r3$eds)),
    c(r3$reg, r3$a, r3$b))

## ═══ O. 자체 사양 입구 ════════════════════════════════════════════════════════════
cat("O 자체 사양 입구\n")
SC_OWN <- RC_STANDING_SCAN_OWN_DEFAULT
t_o1 <- Sys.time(); CO <- rc_standing_lane_candidates(SC_OWN, ROOT, tau = TAU); s_o1 <- as.numeric(difftime(Sys.time(), t_o1, units = "secs"))
icw <- grepl("_ICW$", CO$dir)
reg_p1 <- vapply(pr_get(pr_load(ROOT), "P1_RETURN")$rounds %||% list(), function(r) if (file.exists(rc_abs(r$prereg %||% "x", ROOT))) r$round_id else NA_character_, "")
p1r04 <- "P1R04_combiner_t1_icw" %in% reg_p1; want_icw <- if (p1r04) "P1R04_combiner_t1_icw" else ""
srs <- function(x) { v <- strsplit(x, ",", fixed = TRUE)[[1]]; v[nzchar(v)] }
## 원천 라운드 기대(등록부대로 · 11-13 P1R04 등록 = T1 15 + 같은 배치 T0 기준 15): T0 = P1R03 을 품고 · T1 = P1R04 등록 여부대로 · 모든 이름 = 등록된 P1 라운드
src_ok <- all(vapply(CO[icw == FALSE]$source_rounds, function(x) "P1R03_factor_family_composites" %in% srs(x), TRUE)) &&
  all(vapply(CO[icw == TRUE]$source_rounds, function(x) identical("P1R04_combiner_t1_icw" %in% srs(x), p1r04) && (p1r04 || !length(srs(x))), TRUE)) &&
  all(unlist(lapply(CO$source_rounds, srs)) %in% reg_p1)
chk(sprintf("O1 실제 FC_* 30개(읽기만 · 실제 등록부 · %.0f초) — 전부 통과 · T1 15 = orientation_layer · T0 15 = factor_db_static · 원천 라운드 T0 ∋ P1R03 · T1 = 등록부대로(P1R04 등록 %s) · 자체 사양 열",
            s_o1, p1r04),
    nrow(CO) == 30L && all(CO$eligible) && sum(icw) == 15L && all(CO[icw == TRUE]$orientation == "orientation_layer") && all(CO[icw == FALSE]$orientation == "factor_db_static") &&
      src_ok && all(CO$where == "own_spec") && all(CO$long_leg == "na:own_spec" & CO$breadth == "na:own_spec" & CO$grid == "na:own_spec") &&
      all(c("family_root", "own_spec", "own_spec_md5", "generator", "families", "source_rounds") %in% names(CO)) && !anyNA(CO$family_root),
    paste(CO$dir, CO$reasons, CO$orientation, CO$source_rounds, sep = ":", collapse = " | "))
## O2 임시 사본 돌연변이 — 음성(사본 그대로 = 통과) · 양성(사유 하나씩)
LANE_M <- file.path(SB, "lane_mut")
invisible(cp_fc("FC_FAM_value", LANE_M)); D_ICW <- cp_fc("FC_TOTAL_ICW", LANE_M)
d_eng <- cp_fc("FC_FAM_value", LANE_M, "FC_X_ENG"); cat(" ", file = file.path(d_eng, "engine.R"), append = TRUE)
d_nos <- cp_fc("FC_FAM_value", LANE_M, "FC_X_NOSPEC"); unlink(file.path(d_nos, "own_spec.json"))
d_cor <- cp_fc("FC_FAM_value", LANE_M, "FC_X_CORE"); s_c <- rc_json_read(file.path(d_cor, "own_spec.json"))
s_c$core$members[[1]]$s_reg <- -as.integer(s_c$core$members[[1]]$s_reg); rc_json_write(s_c, file.path(d_cor, "own_spec.json"))         # core 변조 · spec_md5 그대로
d_gen <- cp_fc("FC_FAM_value", LANE_M, "FC_X_GENMD5"); s_g <- rc_json_read(file.path(d_gen, "own_spec.json"))
s_g$core$generator_md5 <- "00000000000000000000000000000000"; s_g$spec_md5 <- .rcs_own_core_md5(s_g$core); rc_json_write(s_g, file.path(d_gen, "own_spec.json"))   # 사양은 온전 · 생성기 md5 만 다름
W_FROM <- ".fce_w <- ifelse(is.finite(.fce_a) & .fce_a > 0, .fce_a, 0)"; W_TO <- ".fce_w <- .fce_a; .fce_w[!is.finite(.fce_w)] <- 0"
rd_txt <- function(p) { x <- rawToChar(readBin(p, "raw", n = file.info(p)$size)); Encoding(x) <- "UTF-8"; x }
n_fx <- function(x, pat) lengths(regmatches(x, gregexpr(pat, x, fixed = TRUE)))
d_wgt <- cp_fc("FC_TOTAL_ICW", LANE_M, "FC_X_WEIGHT"); TW0 <- rd_txt(file.path(D_ICW, "engine.R")); TW1 <- sub(W_FROM, W_TO, TW0, fixed = TRUE)
writeBin(charToRaw(TW1), file.path(d_wgt, "engine.R"))
SCM <- SC_OWN; SCM$lane_root <- LANE_M
CM <- rc_standing_lane_candidates(SCM, ROOT, tau = TAU)
det_of <- function(C, d) C[dir == d]$own_detail
chk("O2a 음성 — FC_FAM_value · FC_TOTAL_ICW 사본(바이트 그대로 · 저장소 밖) = 통과", isTRUE(CM[dir == "FC_FAM_value"]$eligible) && isTRUE(CM[dir == "FC_TOTAL_ICW"]$eligible),
    paste(CM[dir %in% c("FC_FAM_value", "FC_TOTAL_ICW")]$reasons, collapse = "|"))
chk("O2b 엔진 1바이트 수정 = own_generator_mismatch(엔진 md5 · 재생성 md5) · own_spec 사유 아님",
    has_reason(CM, "FC_X_ENG", "own_generator_mismatch") && !has_reason(CM, "FC_X_ENG", "own_spec_missing") && grepl("engine_md5", det_of(CM, "FC_X_ENG")) && grepl("regen_md5", det_of(CM, "FC_X_ENG")),
    det_of(CM, "FC_X_ENG"))
chk("O2c own_spec.json 삭제 = own_spec_missing · O2d core 변조(spec_md5 그대로) = own_spec_missing(core md5 ≠ spec_md5)",
    has_reason(CM, "FC_X_NOSPEC", "own_spec_missing") && has_reason(CM, "FC_X_CORE", "own_spec_missing") && grepl("core md5", det_of(CM, "FC_X_CORE")),
    paste(CM[dir %in% c("FC_X_NOSPEC", "FC_X_CORE")]$reasons, collapse = "|"))
chk("O2e 생성기 md5 만 다름(사양 온전) = own_generator_mismatch(generator_md5) · own_spec_missing 아님",
    has_reason(CM, "FC_X_GENMD5", "own_generator_mismatch") && !has_reason(CM, "FC_X_GENMD5", "own_spec_missing") && grepl("generator_md5", det_of(CM, "FC_X_GENMD5")), det_of(CM, "FC_X_GENMD5"))
SCU <- SCM; SCU$generators <- SCU$generators[1]
CU <- rc_standing_lane_candidates(SCU, ROOT, tau = TAU)
chk("O2f 생성기 목록에서 T1 생성기를 빼면 FC_TOTAL_ICW 사본 = own_generator_unknown · T0 사본은 통과(음성)",
    has_reason(CU, "FC_TOTAL_ICW", "own_generator_unknown") && isTRUE(CU[dir == "FC_FAM_value"]$eligible), CU[dir == "FC_TOTAL_ICW"]$reasons)
SCN <- SCM; SCN$orientation_admit <- list("engine_native")
CN <- rc_standing_lane_candidates(SCN, ROOT, tau = TAU)
chk("O2g 방향 층 허용에서 orientation_layer 를 빼면 T1 사본 = dynamic_sign · T0 사본(factor_db_static)은 통과(음성)",
    has_reason(CN, "FC_TOTAL_ICW", "dynamic_sign") && isTRUE(CN[dir == "FC_FAM_value"]$eligible), CN[dir == "FC_TOTAL_ICW"]$reasons)
s_ok <- SO; s_nt <- SO; s_nt$standing_cfg$track <- NULL; s_mt <- SO; s_mt$standing_cfg$track <- "lane"
s_lo <- SL; s_lo$standing_cfg$scan$orientation_admit <- list("engine_native", "orientation_layer")
s_ga <- SO; s_ga$standing_cfg$scan$generators[[1]]$path <- file.path(ROOT, "02_Infrastructure/factor_db/fc_engine_gen.R")
vv <- function(s) err_of(rc_standing_validate(s, ROOT, check_pin = FALSE, check_files = FALSE))
chk("O2h 사양 검사 — 자체 사양 판(그대로) 통과 · track 없음 · 원천과 갈래 어긋남 · 레인 판의 orientation_layer · 생성기 절대 경로 = 거부",
    identical(vv(s_ok), "") && grepl("track 없음", vv(s_nt)) && grepl("갈래", vv(s_mt)) && grepl("orientation_layer", vv(s_lo)) && grepl("저장소 상대", vv(s_ga)),
    c(vv(s_ok), vv(s_nt), vv(s_mt), vv(s_lo), vv(s_ga)))
## W — orientation_layer 허용 조건 실증(판단 T1 C-20261113-002): 본문 실행 단정이 실제로 멈춘다 · 같은 사본은 재생성 대조에서 빠진다
cat("W 가중 단정(T1 엔진 본문)\n")
CAL <- local({ q <- dplyr::filter(arrow::open_dataset(file.path(ROOT, ".cache", "rawdata.parquet")), Date >= as.Date("2022-08-01"), Date <= as.Date("2022-09-30"))
  sort(unique(as.Date(dplyr::collect(dplyr::distinct(dplyr::select(q, Date)))$Date))) })
WCH <- file.path(SB, "w_child.R")
writeLines(c("job <- readRDS(commandArgs(trailingOnly = TRUE)[1])", "e <- new.env(parent = globalenv())",
             "e$RAWDATA <- data.table::data.table(Date = job$dates); e$.RP_START_DATE <- job$start",
             "dir.create(job$diag, recursive = TRUE, showWarnings = FALSE); options(fce.diag_dir = job$diag)",
             "err <- tryCatch({ sys.source(job$engine, envir = e); NA_character_ }, error = function(z) conditionMessage(z))",
             "n <- if (exists('FACTORS', envir = e, inherits = FALSE)) nrow(get('FACTORS', envir = e, inherits = FALSE)) else NA_integer_",
             "saveRDS(list(err = err, n = n, md5 = unname(tools::md5sum(job$engine))), job$out)"), WCH)
wrun <- function(eng, tag) {
  jf <- file.path(SB, paste0("w_", tag, ".rds")); of <- file.path(SB, paste0("w_", tag, "_out.rds"))
  saveRDS(list(engine = eng, dates = CAL, start = as.Date("2022-08-01"), diag = file.path(SB, paste0("w_", tag, "_diag")), out = of), jf)
  Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)   # 엔진의 루트 판독(CLAUDE_PROJECT_DIR → QM_ROOT) — 자식이 물려받는다
  o <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(shQuote(WCH), shQuote(jf)), stdout = TRUE, stderr = TRUE))
  if (file.exists(of)) readRDS(of) else list(err = paste("자식 결과 없음:", paste(tail(o, 3), collapse = " | ")), n = NA_integer_, md5 = NA_character_)
}
w_ok <- n_fx(TW0, W_FROM) == 1L && n_fx(TW0, W_TO) == 0L && n_fx(TW1, W_FROM) == 0L && n_fx(TW1, W_TO) == 1L &&
  identical(sub(W_TO, W_FROM, TW1, fixed = TRUE), TW0) && !inherits(tryCatch(parse(file = file.path(d_wgt, "engine.R"), keep.source = FALSE), error = function(e) e), "error")
chk("W1 돌연변이 치환 성사 — 가중 줄 원본 1곳 → 사본 0 · 새 줄 0 → 1 · 되돌리면 원본과 바이트 동일 · parse 통과 · 저장소 밖", w_ok && !startsWith(tolower(d_wgt), tolower(ROOT)))
wr0 <- wrun(file.path(D_ICW, "engine.R"), "orig"); wr1 <- wrun(file.path(d_wgt, "engine.R"), "mut")
chk(sprintf("W2 원본 사본 — 짧은 창(2022-08 ~ 09 · 거래일 %d)에서 멈추지 않는다(FACTORS 행 > 0 · 진단은 임시 폴더)", length(CAL)),
    is.na(wr0$err) && isTRUE(wr0$n > 0) && identical(wr0$md5, md5(file.path(D_ICW, "engine.R"))), wr0$err)
chk("W3 가중 돌연변이 — 같은 창에서 '가중 단정 위반'으로 멈춘다(부호 고정 · 비음수 단정이 실행에서 작동) · 그 사본은 스캔에서 own_generator_mismatch(재생성 md5 불일치)",
    grepl("가중 단정 위반", wr1$err %||% "") && identical(wr1$md5, md5(file.path(d_wgt, "engine.R"))) && has_reason(CM, "FC_X_WEIGHT", "own_generator_mismatch") &&
      grepl("regen_md5", det_of(CM, "FC_X_WEIGHT")), c(wr1$err, det_of(CM, "FC_X_WEIGHT")))
## O3 enqueue 시행 수 — 등록된 자체 사양 판 스캔(실제 경로) + 가짜 맥락(경우별)
nf_v <- rc_standing_nf_prior("FC:value", ROOT)                         # 스캔 전 계보 최댓값(스캔이 넣는 줄이 다시 세지 않게)
sco <- tryCatch(rc_standing_scan(RD_OWN, registry_path = REGT), error = function(e) e)
LO <- file.path(SAR, "stage_artifacts/programs/P1_RETURN/P1S91_v4own/standing_ledger.jsonl")
IO <- if (inherits(sco, "error")) list() else rc_standing_items(rc_standing_ledger_read(LO))
it_by <- function(I, rx) { x <- Filter(function(it) grepl(rx, .rcs_str(it$engine_path) %||% ""), I); if (length(x)) x[[1]] else NULL }
iv <- it_by(IO, "FC_FAM_value/engine.R$"); ii <- it_by(IO, "FC_FAM_value_ICW/engine.R$")
ctx_o <- tryCatch(rc_standing_context(RD_OWN, registry_path = REGT), error = function(e) NULL)
chk(sprintf("O3a 판 스캔 → enqueue — T0 사본: origin own_spec · 원천 ∋ P1R03 · 계보 FC:value · n_family = 계보 최댓값 %d 그대로(+1 없음) · T1 사본: 원천 '%s' · 원장 줄 track own_spec · 칸 사양 재생성 = R2",
            nf_v, if (is.null(ii)) "?" else paste(unlist(ii$handoff$source_rounds), collapse = ",")),
    !inherits(sco, "error") && !is.null(iv) && !is.null(ii) && identical(iv$handoff$origin, "own_spec") && "P1R03_factor_family_composites" %in% unlist(iv$handoff$source_rounds) &&
      identical(iv$family_root, "FC:value") && identical(as.integer(iv$n_family), as.integer(nf_v)) && identical(iv$track, "own_spec") &&
      identical(paste(unlist(ii$handoff$source_rounds), collapse = ","), want_icw) && identical(as.integer(ii$n_family), 2L) && !is.null(ctx_o) &&
      identical(rc_standing_regen_md5(iv, ctx_o), iv$cell_spec_md5) && identical(rc_standing_regen_md5(ii, ctx_o), ii$cell_spec_md5),
    if (inherits(sco, "error")) conditionMessage(sco) else paste(names(IO), collapse = ","))
FCTX <- list(root = ROOT, ledger = file.path(SB, "fake_ctx", "standing_ledger.jsonl"), cfg = list(edition = 1L, rejudge_prior_editions = FALSE, generator_pin = list(fn_md5 = "x")),
             spec = list(program = "P1_RETURN", round_id = "P1S89_v4enq"), tag = "P1S89", round_dir = file.path(SB, "fake_ctx"), prereg_md5 = "v4test", track = "own_spec")
enq <- function(src, fam, ho) { ep <- file.path(ROOT, "04_Research/strategies", src, "engine.R"); os <- rc_json_read(file.path(dirname(ep), "own_spec.json"))
  rc_standing_enqueue(ep, os$root_paper, fam, FCTX$round_dir, handoff = ho, source = "scan", root = ROOT, ctx = FCTX)$code }
e1 <- enq("FC_FAM_quality", "FC:quality", list(origin = "own_spec", source_rounds = list()))
e2 <- enq("FC_FAM_momentum", "FC:momentum", list(origin = "own_spec", source_rounds = list("P1R03_factor_family_composites")))
e3 <- enq("FC_FAM_growth", "FC:growth", list())
e4 <- enq("FC_FAM_technical", "FC:v4_no_family", list(origin = "own_spec", source_rounds = list("P1R03_factor_family_composites")))
IF <- rc_standing_items(rc_standing_ledger_read(FCTX$ledger)); nfo <- function(cd) as.integer(IF[[cd]]$n_family)
nq <- rc_standing_nf_prior("FC:quality", ROOT); nm <- rc_standing_nf_prior("FC:momentum", ROOT); ng <- rc_standing_nf_prior("FC:growth", ROOT)
chk(sprintf("O3b 시행 수 — 원천 라운드 있음 = 계보 최댓값 그대로(momentum %d) · 원천 없음 = +1(quality %d → %d) · 레인 꼴(origin 없음) = v3 공식 +1(growth) · 원천은 있으나 그 계보 회계 없음 = +1 · 넷 다 재생성 = R2",
            nm, nq, max(nq, 1L) + 1L),
    nm >= 1L && identical(nfo(e2), as.integer(nm)) && identical(nfo(e1), as.integer(max(nq, 1L) + 1L)) && identical(nfo(e3), as.integer(max(ng, 1L) + 1L)) &&
      identical(nfo(e4), 2L) && all(vapply(c(e1, e2, e3, e4), function(cd) identical(rc_standing_regen_md5(IF[[cd]], FCTX), IF[[cd]]$cell_spec_md5), TRUE)) &&
      grepl("재측정", IF[[e2]]$n_trials_basis) && grepl("원천 라운드 없음", IF[[e1]]$n_trials_basis),
    paste(nfo(e1), nfo(e2), nfo(e3), nfo(e4)))
## O4 레인 갈래 = v3 — 실제 RP_AUTO_* 드라이런(읽기만 · 같은 등록부 · 같은 판독 함수)
t_o4 <- Sys.time(); CL4 <- rc_standing_lane_candidates(RC_STANDING_SCAN_DEFAULT, ROOT, tau = TAU)
CL3 <- run_core("v3", '.res <- as.data.frame(rc_standing_lane_candidates(RC_STANDING_SCAN_DEFAULT, rc_root(), tau = "2022-12-31"))', "lane_v3")
chk(sprintf("O4 레인 입구(lane_handoff) 스캔 표 = v3 표(실제 RP_AUTO_* %d개 · 열 · 값 · %.0f초)", nrow(CL4), as.numeric(difftime(Sys.time(), t_o4, units = "secs"))),
    nrow(CL4) > 0L && identical(names(CL4), names(CL3)) && isTRUE(all.equal(as.data.frame(CL4), CL3, check.attributes = FALSE)), setdiff(names(CL4), names(CL3)))

## ═══ 합성 상설 원장 · 원천 라운드 도구(Q · P · C) ═══════════════════════════════════════
paper <- function(k) list(url = paste0("https://example.org/paper/", k), title = paste("시험 논문", k), paper_key = k)
dir.create(file.path(SB, "pspecs"), showWarnings = FALSE)
pspec <- function(code, eng, k) { p <- file.path(SB, "pspecs", paste0(code, ".json")); rc_json_write(rc_p1_cell_spec(code, eng, paper(k), k, 1L, "v4 시험", root = ROOT), p); p }
BA <- list(rule = "month_snap_v1", n_engine_dates = 110L, n_cell_dates = 108L, n_moved = 108L, n_superseded = 0L, n_offcal = 0L, max_lag_td = 21L, start = "2000-01-01",
           from_cache = FALSE, first_engine_date = "2000-01-14", first_cell_date = "2000-01-31", n_cell_dates_from_start = 106L, base_kind = "factors")
mk_art2 <- function(nm, diag_key = NULL) { a <- file.path(SB, "art", nm); dir.create(a, recursive = TRUE, showWarnings = FALSE)
  rc_json_write(list(run_id = "RP_20261111_090000_t", essence_grade = "C", grade_scheme = "test_fixture"), file.path(a, "authoritative_remeasure.json"))
  if (!is.null(diag_key)) rc_json_write(list(schema = "rf_engine_diag_v1", cell_code = nm, base_alignment = setNames(list(BA), diag_key)), file.path(a, "rf_engine_diag.json"))
  a }
ctxp <- function(sa, rid, ed, track) list(ledger = file.path(sa, "stage_artifacts/programs/P1_RETURN", rid, "standing_ledger.jsonl"), spec = list(round_id = rid),
                                          cfg = list(edition = ed), prereg_md5 = "v4test", track = track)
put <- function(ctx, code, eng, k, q, ho = list(), p2 = NULL) {
  sp <- pspec(code, eng, k)
  rc_standing_append(ctx, list(event = "enqueue", code = code, engine = code, role = "variant", source = "scan", engine_path = eng, engine_md5 = md5(eng),
                               cell_spec = sp, cell_spec_md5 = md5(sp), paper = paper(k), family_root = k, n_family = 1L, handoff = ho))
  rc_standing_append(ctx, list(event = "measure", code = code, ok = TRUE, fp_same = TRUE, artifacts = mk_art2(code)))
  rc_standing_append(ctx, list(event = "verdict", code = code, qualify = q, visible = list(uc_vis = 0.6)))
  if (!is.null(p2)) rc_standing_append(ctx, list(event = "superfan", kind = "pass", codes = list(code), p2 = p2, t2 = "R-T2-x"))
  invisible(code)
}
own_ho <- function(fam, src = character(0)) list(origin = "own_spec", own_spec = "x/own_spec.json", own_spec_md5 = "x", generator = "02_Infrastructure/factor_db/fc_engine_gen.R",
                                                families = as.list(fam), source_rounds = as.list(src), declared_at = "2026-11-12T22:25:51+0900")
mk_eng <- function(nm) { d <- file.path(SB, "strategies", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("## 시험 엔진(v4) — 실행하지 않는다", "FACTORS <- NULL", strrep("# 채움\n", 30), paste("##", nm)), file.path(d, "engine.R")); file.path(d, "engine.R") }
FCP <- function(src) { d <- file.path(SB, "strategies", src); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (!isTRUE(file.copy(file.path(ROOT, "04_Research/strategies", src, "engine.R"), file.path(d, "engine.R"), overwrite = TRUE))) stop("복사 실패: ", src); file.path(d, "engine.R") }

## ═══ Q. 자격 통과 표 — 갈래 둘에 걸친 같은 칸 ═══════════════════════════════════════════
cat("Q 자격 통과 표(갈래)\n")
SAQ <- file.path(SB, "saq"); EX <- mk_eng("RP_AUTO_V4QX"); EY <- mk_eng("RP_AUTO_V4QY"); EZ <- mk_eng("RP_AUTO_V4QZ")
QL <- ctxp(SAQ, "P1S86_v4ql", 2L, "lane"); QO <- ctxp(SAQ, "P1S85_v4qo", 1L, "own_spec")
invisible({ put(QL, "QL_X", EX, "9951.00001", TRUE); put(QO, "QO_X", EX, "9951.00001", FALSE, own_ho("value"))      # 레인 판 2 통과 · 자체 사양 판 1 미달(같은 칸)
            put(QL, "QL_Y", EY, "9951.00002", TRUE); put(QO, "QO_Y", EY, "9951.00002", TRUE, own_ho("value"))       # 둘 다 통과
            put(QL, "QL_Z", EZ, "9951.00003", TRUE) })                                                              # 한 갈래만
QR <- c("P1S86_v4ql", "P1S85_v4qo")
QQ <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SAQ)[round_id %in% QR]
QQ3 <- run_core("v3", sprintf('.res <- as.data.frame(rc_standing_qualified("P1_RETURN", root = rc_root(), sa_root = "%s")[round_id %%in%% c("P1S86_v4ql", "P1S85_v4qo")])', SAQ), "qual_v3")
chk("Q1 두 갈래에 걸친 같은 칸 — 레인 판 2 통과 + 자체 사양 판 1 미달 = 자격 없음(v4 · fail-closed) · 대조 v3 = 판 번호 큰 레인 판 통과가 남는다(fail-open)",
    !any(c("QL_X", "QO_X") %in% QQ$code) && "QL_X" %in% QQ3$code, paste(QQ$code, "|", QQ3$code))
chk("Q2 두 갈래 모두 통과 = 그 칸 한 행(판정 시각이 늦은 갈래) · 한 갈래만 = v3 와 같다(음성 — QL_Z 양쪽 모두)",
    sum(QQ$code %in% c("QL_Y", "QO_Y")) == 1L && "QL_Z" %in% QQ$code && "QL_Z" %in% QQ3$code, paste(QQ$code))
qy <- QQ[code %in% c("QL_Y", "QO_Y")]
chk("Q3 열 추가 — track(원장 줄 머리) · origin(자체 사양 = own_spec · 레인 = lane) · families · source_rounds · superfan_pass_p2 · paper_title · paper_url",
    all(c("track", "origin", "own_spec", "own_spec_md5", "families", "source_rounds", "superfan_pass_p2", "paper_title", "paper_url") %in% names(QQ)) &&
      identical(QQ[code == "QL_Z"]$origin, "lane") && identical(QQ[code == "QL_Z"]$track, "lane") && nrow(qy) == 1L &&
      (if (qy$code == "QO_Y") identical(qy$origin, "own_spec") && identical(qy$families, "value") else identical(qy$origin, "lane")), paste(names(QQ), collapse = ","))

## ═══ P. 기저 풀 — 철학 P2 판독(두 갈래) · 보류 · 저위험(엔진 단위) ═════════════════════════════
cat("P 기저 풀\n")
SAP <- file.path(SB, "sap")
E_OV <- FCP("FC_FAM_value"); E_OD <- FCP("FC_FAM_defense"); E_ON <- FCP("FC_FAM_quality"); E_OW <- FCP("FC_FAM_growth"); E_OH <- FCP("FC_FAM_momentum")
E_OT <- FCP("FC_TOTAL_EW"); E_R1 <- FCP("FC_FAM_accrual"); E_R2 <- FCP("FC_FAM_crowding"); E_R3 <- FCP("FC_FAM_leverage"); E_L1 <- FCP("FC_FAM_risk"); E_L2 <- FCP("FC_FAM_regime")
E_LA <- mk_eng("RP_AUTO_V4LA"); E_LB <- mk_eng("RP_AUTO_V4LB")
rc_json_write(list(paper_key = "T_LA", paper_url = "https://example.org/paper/T_LA"), file.path(dirname(E_LA), "lane_provenance.json"))
mk_src_round <- function(rid, cells) {   # 원천 라운드(등록 · 칸 사양 · 측정 기록 · 산출 폴더) — 사전등록 핀에 엔진 md5
  rd <- file.path(SB, "round", rid); dir.create(file.path(rd, "specs"), recursive = TRUE, showWarnings = FALSE); dir.create(file.path(rd, "results"), showWarnings = FALSE)
  pc <- list(); pins <- list()
  for (c in cells) {
    sp <- file.path(rd, "specs", paste0(c$code, ".json")); rc_json_write(rc_p1_cell_spec(c$code, c$eng, paper(c$code), "FC:v4test", 1L, "v4 시험", root = ROOT), sp)
    a <- file.path(SB, "art", paste0("src_", c$code)); dir.create(a, recursive = TRUE, showWarnings = FALSE)
    rc_json_write(list(ok = TRUE, artifacts = a, code = c$code), file.path(rd, "results", paste0(c$code, ".json")))
    pc[[length(pc) + 1L]] <- list(code = c$code, engine = c$code, role = "variant", spec = sp, md5 = md5(sp))
    pins[[length(pins) + 1L]] <- list(path = .rcs_repo_rel(c$eng, ROOT), md5 = md5(c$eng))
  }
  rc_json_write(list(round_id = rid, program = "P1_RETURN", template = "p1_qualification"), file.path(rd, "round_spec.json"))
  rel <- file.path("stage_artifacts/programs/P1_RETURN", rid, "prereg.json"); pf <- file.path(SAR, rel)
  rc_json_write(list(schema = "round_core_prereg_v1", program = "P1_RETURN", round_id = rid, status = "registered", spec = list(standing = FALSE, template = "p1_qualification"),
                     cells = pc, pins = list(files = pins)), pf)
  list(dir = rd, entry = list(round_id = rid, prereg = rel, prereg_md5 = md5(pf), status = "registered"))
}
SR97 <- mk_src_round("P1R97_v4src", list(list(code = "P1R97_A_C0", eng = E_OV), list(code = "P1R97_B_C0", eng = E_R1), list(code = "P1R97_C_C0", eng = E_R2),
                                         list(code = "P1R97_D_C0", eng = E_L1), list(code = "P1R97_E_C0", eng = E_L2)))
SR98 <- mk_src_round("P1R98_v4src2", list(list(code = "P1R98_F_C0", eng = E_R3)))
A_LA <- mk_art2("lane_LA"); A_LB <- mk_art2("lane_LB")
itl <- function(k, eng, art, ...) modifyList(list(key = paste0("engine:", k), kind = "engine", engine_path = eng, artifacts = art, grade = "F", implementation_suspect = FALSE,
                                                 has_short = FALSE, audit_verdict = "faithful", paper_key = k, title = paste("시험 엔진", k), enqueued_at = "2026-11-11T10:00:00+0900"), list(...))
REGP <- file.path(SB, "reg_pool.json")
rc_json_write(list(schema = REG0$schema, target_spec = list(), programs = list(
  list(id = "P1_RETURN", queue = list(itl("T_LA", E_LA, A_LA), itl("T_LB", E_LB, A_LB, implementation_suspect = TRUE)), consumed = list(), rounds = list(SR97$entry, SR98$entry)),
  list(id = "P4_ASSEMBLY", queue = list(), rounds = list())), paper_routing = list(unrouted = list())), REGP)
FDVL <- file.path(SB, "factor_db_vintage.json")
rc_json_write(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T-REPAIR", completed_at = "2026-11-10T11:26:00+09:00", scope = "all"))), FDVL)
DRP <- file.path(SB, "decision_register.json")
rc_json_write(list(schema = "decision_register_v1", items = list(list(id = "TEST-LOWRISK-OK", status = "resolved"), list(id = "TEST-LOWRISK-OPEN", status = "open"))), DRP)
LEDP <- file.path(SB, "q_judgment_ledger_p.json")
pf2 <- function(tag, trig, role = "philosophy") sprintf("04_Research/programs/_supervision/superfan/%s20261113_1000_%s_%s.md", if (role == "philosophy") "philosophy/" else "", trig, tag)
PREV <- list(rvw("R-P2-P1S88", "philosophy", "P2", "P1S88_v4pool", pf2("P1S88", "P2")), rvw("R-P2-WRONG", "philosophy", "P2", "P1S01_standing_qualification", pf2("WRONG", "P2")),
             rvw("R-P2-HOLD", "philosophy", "P2", "P1S88_v4pool", pf2("HOLD", "P2"), challenges = list("C-HOLD")),
             rvw("R-P2-P1R97", "philosophy", "P2", "P1R97_v4src", pf2("P1R97", "P2")))
for (cid in c("P4C79_v4own", "P4C78_v4lane")) { tg <- rc_round_tag(cid)
  PREV <- c(PREV, list(rvw(paste0("R-P1-", tg), "philosophy", "P1", cid, sprintf("04_Research/programs/_supervision/superfan/philosophy/20261113_1100_P1_%s.md", tg)),
                       rvw(paste0("R-T1-", tg), "judgment", "T1", cid, pf2(tg, "T1", "judgment")), rvw(paste0("R-P2-", tg), "philosophy", "P2", cid, pf2(tg, "P2c")),
                       rvw(paste0("R-T2-", tg), "judgment", "T2", cid, pf2(tg, "T2", "judgment")))) }
rc_json_write(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = PREV, challenges = list(
  list(id = "C-HOLD", review = "R-P2-HOLD", grade = "stop", status = "rebutted", hold_request = TRUE, responses = list(list(by = "Q", text = "반론"))))), LEDP)
## 원천 라운드 영수증 — 쓰기 도우미 거부(양성) · 쓰기(음성)
RW <- function(id, eng, ...) err_of(rc_philosophy_receipt_write(SR97$dir, id, engines = eng, ledger = LEDP, decision_register = DRP, ...))
one <- function(eng, ...) setNames(list(list(hold = FALSE, stop = FALSE, note = "방향 향함", ...)), eng)
rw_noid <- RW("R-P2-NOPE", one(E_R1)); rw_open <- RW("R-P2-P1R97", one(E_L1, release_decision = "TEST-LOWRISK-OPEN"))
rw_miss <- RW("R-P2-P1R97", one(E_L1, release_decision = "NO-SUCH-DECISION")); rw_out <- RW("R-P2-P1R97", one(E_ON))
REN <- setNames(list(list(hold = FALSE, stop = FALSE, note = "방향 향함 · 실패 형태 기록"), list(hold = TRUE, stop = FALSE, note = "숨은 현금 의심 — 도훈 확인"),
                     list(hold = FALSE, stop = FALSE, note = "저β 엔진 허용 결정", release_decision = "TEST-LOWRISK-OK"), list(hold = FALSE, stop = FALSE, note = "확인 결정 없음")),
                c(E_R1, E_R2, E_L1, E_L2))
rw_ok <- RW("R-P2-P1R97", REN); RCF <- file.path(SR97$dir, "results", "philosophy_receipt.json"); RC1 <- if (file.exists(RCF)) rc_json_read(RCF) else list()
chk("P0 영수증 쓰기 도우미 — 원장에 없는 p2 id · 미해결(open) release_decision · 결정 기록부에 없는 id · 그 라운드 칸 엔진이 아닌 경로 = 거부 · 확인된 id = 원자적 쓰기(rc_philosophy_receipt_v1 · 엔진 4 · release_decision)",
    grepl("철학 P2 리뷰 확인 실패", rw_noid) && grepl("resolved", rw_open) && grepl("resolved", rw_miss) && grepl("기저 엔진이 아니다", rw_out) && identical(rw_ok, "") &&
      identical(RC1$schema, "rc_philosophy_receipt_v1") && identical(RC1$round_id, "P1R97_v4src") && length(RC1$engines) == 4L &&
      identical(RC1$engines[[.rcs_repo_rel(E_L1, ROOT)]]$release_decision, "TEST-LOWRISK-OK") && is.null(RC1$engines[[.rcs_repo_rel(E_L2, ROOT)]]$release_decision),
    c(rw_noid, rw_open, rw_miss, rw_out, rw_ok))
rc_json_write(list(schema = "rc_philosophy_receipt_v1", round_id = "P1R98_v4src2", p2_review_id = "R-P2-NOPE", written_at = "x",     # 위조 영수증(원장에 없는 id) — 손으로 쓴 파일
                   engines = setNames(list(list(hold = FALSE, stop = FALSE, note = "")), .rcs_repo_rel(E_R3, ROOT))), file.path(SR98$dir, "results", "philosophy_receipt.json"))
PQ <- ctxp(SAP, "P1S88_v4pool", 1L, "own_spec"); PL <- ctxp(SAP, "P1S87_v4lanep", 1L, "lane")
FAM14 <- unlist(rc_json_read(file.path(ROOT, "04_Research/strategies/FC_TOTAL_EW/own_spec.json"))$core$families)
invisible({
  put(PQ, "P1S88_OV", E_OV, "FC_FAM_value", TRUE, own_ho("value", "P1R97_v4src"), p2 = "R-P2-P1S88")   # 갈래 ① 확인 · 가치(저위험 밖)
  put(PQ, "P1S88_OD", E_OD, "FC_FAM_defense", TRUE, own_ho("defense"), p2 = "R-P2-P1S88")             # 저위험 · 영수증 없음
  put(PQ, "P1S88_ON", E_ON, "FC_FAM_quality", TRUE, own_ho("quality"))                                 # 기록 없음 · 원천 없음
  put(PQ, "P1S88_OW", E_OW, "FC_FAM_growth", TRUE, own_ho("growth"), p2 = "R-P2-WRONG")                # 대상 다른 P2
  put(PQ, "P1S88_OH", E_OH, "FC_FAM_momentum", TRUE, own_ho("momentum"), p2 = "R-P2-HOLD")             # P2 리뷰에 열린 보류
  put(PQ, "P1S88_OT", E_OT, "FC_TOTAL_EW", TRUE, own_ho(FAM14), p2 = "R-P2-P1S88")                     # 토탈(가족 14 — 저위험 셋과 겹침)
  put(PQ, "P1S88_R1", E_R1, "FC_FAM_accrual", TRUE, own_ho("accrual", "P1R97_v4src"))                  # 영수증 hold false
  put(PQ, "P1S88_R2", E_R2, "FC_FAM_crowding", TRUE, own_ho("crowding", "P1R97_v4src"))                # 영수증 hold true
  put(PQ, "P1S88_R3", E_R3, "FC_FAM_leverage", TRUE, own_ho("leverage", "P1R98_v4src2"))               # 위조 영수증
  put(PQ, "P1S88_L1", E_L1, "FC_FAM_risk", TRUE, own_ho("risk", "P1R97_v4src"))                        # 저위험 · 영수증 release resolved
  put(PQ, "P1S88_L2", E_L2, "FC_FAM_regime", TRUE, own_ho("regime", "P1R97_v4src"))                    # 저위험 · 영수증 release 없음
  put(PL, "P1S87_LA", E_LA, "T_LA", TRUE, list(base_id = "RP_V4_LA", program = "P1_RETURN", where = "queue"))
  put(PL, "P1S87_LB", E_LB, "T_LB", TRUE, list(base_id = "RP_V4_LB", program = "P1_RETURN", where = "queue")) })
QP <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SAP)[round_id %in% c("P1S88_v4pool", "P1S87_v4lanep")]
POOL4 <- rc_p4_base_pool(ROOT, registry_path = REGP, standing = QP, fdv_ledger_path = FDVL, judgment_ledger = LEDP, decision_register = DRP)
row_of <- function(P, cd) P[standing_code == cd]
rsn <- function(P, cd) strsplit(row_of(P, cd)$reason[1], ";", fixed = TRUE)[[1]]
chk("P1 philosophy_unread 양성 — 기록 · 원천 없음(ON) · 대상 다른 P2(OW) · 원장에 없는 id 의 영수증(R3) · 음성 — 갈래 ① 확인(OV = 사유 없음 · 자격)",
    "philosophy_unread" %in% rsn(POOL4, "P1S88_ON") && "philosophy_unread" %in% rsn(POOL4, "P1S88_OW") && "philosophy_unread" %in% rsn(POOL4, "P1S88_R3") &&
      isTRUE(row_of(POOL4, "P1S88_OV")$eligible), paste(POOL4$standing_code, POOL4$reason, sep = "=", collapse = " | "))
chk("P2 갈래 ② 영수증 — hold false = 해소(R1 자격 · 상설 기록 없음) · hold true = philosophy_hold(R2 · unread 아님) · P2 리뷰 열린 보류 = philosophy_hold(OH)",
    isTRUE(row_of(POOL4, "P1S88_R1")$eligible) && identical(rsn(POOL4, "P1S88_R2"), "philosophy_hold") && identical(rsn(POOL4, "P1S88_OH"), "philosophy_hold"),
    paste(row_of(POOL4, "P1S88_R2")$reason, row_of(POOL4, "P1S88_OH")$reason))
chk("P3 저위험(엔진 단위) — release_decision resolved = 해소(L1 risk 자격) · 영수증 항목에 없음 = lowrisk_confirm_pending(L2 regime) · 영수증 없음(OD defense) · 토탈(가족 14 겹침 · OT) = 대기 · 가치(OV) = 사유 없음",
    isTRUE(row_of(POOL4, "P1S88_L1")$eligible) && identical(rsn(POOL4, "P1S88_L2"), "lowrisk_confirm_pending") && identical(rsn(POOL4, "P1S88_OD"), "lowrisk_confirm_pending") &&
      identical(rsn(POOL4, "P1S88_OT"), "lowrisk_confirm_pending") && !("lowrisk_confirm_pending" %in% rsn(POOL4, "P1S88_OV")),
    paste(row_of(POOL4, "P1S88_L2")$reason_detail))
saveRDS(QP, file.path(SB, "qp.rds"))
P3 <- run_core("v3", sprintf('.res <- as.data.frame(rc_p4_base_pool(rc_root(), registry_path = "%s", standing = readRDS("%s"), fdv_ledger_path = "%s"))', REGP, file.path(SB, "qp.rds"), FDVL), "pool_v3")
P3 <- as.data.table(P3); lane_keys <- POOL4[!grepl("^standing:P1S88_v4pool:", key)]$key
QPL <- QP[origin == "lane"]; saveRDS(QPL, file.path(SB, "qpl.rds"))
m3 <- run_core("v3", sprintf('.res <- rc_p4_pool_md5(rc_p4_base_pool(rc_root(), registry_path = "%s", standing = readRDS("%s"), fdv_ledger_path = "%s"))', REGP, file.path(SB, "qpl.rds"), FDVL), "poolmd5_v3")
m4 <- rc_p4_pool_md5(rc_p4_base_pool(ROOT, registry_path = REGP, standing = QPL, fdv_ledger_path = FDVL, judgment_ledger = LEDP, decision_register = DRP))
chk("P4 레인 · 등록부 행 = v3 판정(자식 · 같은 입력 — key · eligible · reason 같음 · 구현 의심 꼬리표 LB 포함) · 레인 행만의 풀 md5 = v3 · 대조: v3 는 자체 사양 행에 새 관문이 없다(ON 자격)",
    length(lane_keys) >= 2L && isTRUE(all.equal(as.data.frame(P3[key %in% lane_keys][order(key), .(key, eligible, reason)]),
                                                as.data.frame(POOL4[key %in% lane_keys][order(key), .(key, eligible, reason)]), check.attributes = FALSE)) &&
      "implementation_suspect" %in% rsn(POOL4, "P1S87_LB") && identical(m3, m4) && isTRUE(P3[standing_code == "P1S88_ON"]$eligible),
    paste(P3[key %in% lane_keys]$reason, "|", POOL4[key %in% lane_keys]$reason))
chk("P5 풀 열 — origin · families · source_rounds · own_spec · paper_url(자체 사양 행) · 레인 행 origin = lane",
    all(c("origin", "families", "source_rounds", "own_spec", "paper_url") %in% names(POOL4)) && identical(row_of(POOL4, "P1S88_OV")$origin, "own_spec") &&
      identical(row_of(POOL4, "P1S88_OV")$source_rounds, "P1R97_v4src") && identical(row_of(POOL4, "P1S87_LA")$origin, "lane") && !is.na(row_of(POOL4, "P1S88_OV")$paper_url))

## ═══ C. 사슬 — 원천 시행 · N5 blend · 닫기 시행 집합 ═══════════════════════════════════════
cat("C 사슬\n")
GD1 <- file.path(SB, "gen", "g1"); dir.create(GD1, recursive = TRUE); invisible(file.copy("04_Research/programs/P4_ASSEMBLY/_generator/g1/step.md", GD1))
rc_json_write(list(schema = "rx_generator_v1", current = "g1", versions = list(list(id = "g1", dir = GD1, files = rxg_files_md5(GD1), created_at = rc_now(), reason = "시험", evidence = list()))), GEN_REG)
RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "S 비열등 여유 tie_eps(시험)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor", source = "헌장 강세 참여(시험)"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0, basis = "정의 — 비악화 = 부모 이하", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장 §5 빈칸 4(시험)"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장 §5 빈칸 2(시험)"))
BUD <- list(max_steps = 5L, max_steps_source = "시험 사양 작성자 지정(시험)", noise_k = 3L, noise_k_source = "시험 사양 작성자 지정(시험)")
FIX_BULL <- function() data.table(start_ym = c("2003-04", "2009-03", "2016-02"), end_ym = c("2004-03", "2010-12", "2017-10"), up_capture = 1)
FIX_CR <- function() data.table(peak_date = c("2002-04-18", "2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2002-09-30", "2008-10-24", "2011-09-26", "2020-03-19"),
                                bm_dd = c(0.30, 0.50, 0.25, 0.35), dd_capture = 1, st_recovery_obs = 100, st_recovery_censored = FALSE)
BETA <- list(c79_k1 = c(up = 0.8, down = 0.9), c79_k2 = c(up = 0.9, down = 0.6))   # k1 = 하락 β ≥ 상승 β · k2 = 반대
MF <- function(artifacts, root, tau, ...) { b <- BETA[[basename(artifacts)]]
  c(list(S_vis = 1, uc_vis = 0.6, dd_capture_median_vis = 0.5, calmar_vis = 1, port_t_vis = 2, cagr_vis = 0.1, sharpe_vis = 1, mdd_vis = 0.2, window = c("2000-01-31", "2022-12-30"),
         bull_vis = FIX_BULL(), crises_vis = FIX_CR()), if (!is.null(b)) list(beta_up_vis = unname(b["up"]), beta_down_vis = unname(b["down"]))) }
RUN <- function(art) function(spec_path, code, out_json, log_dir, root, role) { rc_json_write(list(n = 1L, code = code, ok = TRUE, artifacts = art), out_json); 0L }
free <- function(root) list(state = "free", reason = "", lock = "", blocking = FALSE); FP <- function() "fp-same"
FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "시험 주입"); VINT <- function(root) list(id = "vint-1", n_repairs = 1L)
GPU <- function(engine_path, holder, purpose, root) list(ok = TRUE, need = FALSE, state = "cpu", reason = "시험 주입", release = function() invisible(NULL))
OVK <- row_of(POOL4, "P1S88_OV")$key; CD <- file.path(SB, "chain", "P4C79_v4own")
cn <- err_of(rc_p4_chain_new(CD, "P4C79_v4own", OVK, POOL4, adoption_rules = RULES, budget = BUD, purpose = "v4 자체 사양 기저 시험"))
BCS <- if (file.exists(file.path(CD, "base_cell_spec.json"))) rc_json_read(file.path(CD, "base_cell_spec.json")) else list()
reg79 <- function() err_of(rc_p4_chain_register(CD, POOL4, ROOT, metrics_fun = MF, p1 = "R-P1-P4C79", t1 = "R-T1-P4C79", ledger = LEDP, review_root = RVR, registry_path = REGP))
A_HIDE <- file.path(SB, "art", "src_P1R97_C_C0"); invisible(file.rename(A_HIDE, paste0(A_HIDE, "_hidden")))
e_miss <- reg79(); n_miss <- rc_p4_steps_verify(CD)$n
invisible(file.rename(paste0(A_HIDE, "_hidden"), A_HIDE))
chk("C0 자체 사양 기저 사슬 판 — 기저 칸 사양 = 표준 구성 생성기 · 논문 메타 = 상설 항목 paper(own_spec 경로 · lane_provenance 없음)",
    identical(cn, "") && identical(BCS$root_paper$url, paper("FC_FAM_value")$url) && identical(BCS$p4$paper_url_source, "own_spec"), cn)
chk("C1 원천 라운드 칸 하나의 측정 산출이 없으면 사슬 등록 거부(빠진 칸 이름) · 원장 무기록", grepl("P1R97_v4src:P1R97_C_C0", e_miss) && n_miss == 0L, e_miss)
e_ok <- reg79(); RG <- Filter(function(r) identical(r$event, "chain_registered"), rc_p4_steps_read(CD))
st79 <- if (length(RG)) RG[[1]]$source_trials else list()
chk("C2 다 있으면 등록 — chain_registered.source_trials = 원천 라운드 칸 수(5) · {round_id · code · artifacts} · source_rounds = P1R97 · base_origin own_spec",
    identical(e_ok, "") && length(RG) == 1L && length(st79) == 5L && identical(unlist(RG[[1]]$source_rounds), "P1R97_v4src") && identical(RG[[1]]$base_origin, "own_spec") &&
      setequal(vapply(st79, function(x) x$code, ""), sprintf("P1R97_%s_C0", c("A", "B", "C", "D", "E"))) && all(vapply(st79, function(x) dir.exists(rc_abs(x$artifacts, ROOT)), TRUE)), e_ok)
CD2 <- file.path(SB, "chain", "P4C78_v4lane")
cn2 <- err_of(rc_p4_chain_new(CD2, "P4C78_v4lane", "engine:T_LA", POOL4, adoption_rules = RULES, budget = BUD, purpose = "레인 기저 대조"))
e2r <- err_of(rc_p4_chain_register(CD2, POOL4, ROOT, metrics_fun = MF, p1 = "R-P1-P4C78", t1 = "R-T1-P4C78", ledger = LEDP, review_root = RVR, registry_path = REGP))
RG2 <- Filter(function(r) identical(r$event, "chain_registered"), tryCatch(rc_p4_steps_read(CD2), error = function(e) list()))
chk("C3 음성 — 레인 기저 사슬 등록 = v3 와 같은 기록(source_trials · base_origin 필드 없음)", identical(cn2, "") && identical(e2r, "") && length(RG2) == 1L &&
      is.null(RG2[[1]]$source_trials) && is.null(RG2[[1]]$base_origin), c(cn2, e2r))
A_K0 <- mk_art2("c79_k0", "FC_FAM_value/engine.R"); A_K1 <- mk_art2("c79_k1", "FC_FAM_value/engine.R"); A_K2 <- mk_art2("c79_k2", "FC_FAM_value/engine.R")
bm <- tryCatch(rc_p4_base_measure(CD, ROOT, runner = RUN(A_K0), barrier = free, fingerprint = FP, vintage = VINT, metrics_fun = MF, freshness = FRESH, gpu = GPU), error = function(e) e)
dir.create(file.path(SB, "cells"), showWarnings = FALSE)
## 걸음 칸 = 사슬 머리(마지막 채택 · 없으면 기저)의 칸 사양 + factors 한 축(blend 블록)
stepc <- function(nm, fid, hd) { st <- .rcp4_state(CD, ROOT); s <- rc_json_read(rc_abs(.rcp4_rel(.rcp4_cell_of(st, hd), ROOT), ROOT))
  s$factors <- list(list(id = fid, direction = "registry")); p <- file.path(SB, "cells", paste0(nm, ".json")); rc_json_write(s, p); p }
H <- "가치 팩터를 섞으면 위기 하락 포착이 줄어든다"; MCH <- "저베타 가치 신호를 섞어 하락 구간 노출을 낮춘다"
step <- function(k, nm, fid, art) {
  hd <- .rcp4_state(CD, ROOT)$head_k
  o <- err_of(rc_p4_step_open(CD, k, H, MCH, "blend", stepc(nm, fid, hd), hd, "g1", root = ROOT, pool = POOL4))
  m <- tryCatch(rc_p4_step_measure(CD, k, ROOT, runner = RUN(art), barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPU)$status, error = function(e) conditionMessage(e))
  d <- tryCatch(rc_p4_step_decide(CD, k, root = ROOT, metrics_fun = MF), error = function(e) e)
  list(open = o, measure = m, decide = d)
}
s1 <- step(1L, "c79_s1", "V01_BM", A_K1); s2 <- step(2L, "c79_s2", "V02_EP", A_K2)
ba <- function(s) if (inherits(s$decide, "error")) NA_real_ else as.numeric(s$decide$table$beta_asym_ok_vis)
chk("C4 N5 β 비대칭 — blend 걸음(v4 검사 대상): 하락 β ≥ 상승 β = 0 · 하락 β < 상승 β = 1(양방향 · RC_P4_BETA_ASYM_BLOCKS)",
    identical(bm$status, "measured") && identical(s1$open, "") && identical(s1$measure, "measured") && identical(ba(s1), 0) && identical(s2$open, "") && identical(ba(s2), 1) &&
      "blend" %in% RC_P4_BETA_ASYM_BLOCKS, c(if (inherits(bm, "error")) conditionMessage(bm) else bm$status, s1$open, s1$measure, ba(s1), s2$open, ba(s2)))
SRLOG <- file.path(SB, "sr_log.rds"); FSR <- file.path(SB, "fake_sr.R")
writeLines(c("sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, cfg = NULL, ctx = NULL, expected = NULL) {",
             sprintf("  saveRDS(list(candidate = candidate_dir, trials = trial_dirs, expected = expected), '%s')", SRLOG),
             "  list(status = 'ok', grade_before = 'B', grade_after = 'B', gate_ok = TRUE, reason = 'fake', check = NULL, written = FALSE) }"), FSR)
OUTC <- file.path(SB, "round_outcomes.jsonl")
cl <- err_of(rc_p4_close(CD, "자체 사양 기저 사슬 닫기 시험", probes = c("원천 시행 회계를 다시 본다", "닫기 시행 집합을 다시 본다"), root = ROOT, outcomes_path = OUTC,
                         registry_path = REGP, philosophy_p2 = "R-P2-P4C79", superfan_t2 = "R-T2-P4C79", ledger = LEDP, review_root = RVR, regrade_file = FSR,
                         gate_file = file.path(SB, "no_gate.R"), register_file = file.path(SB, "no_register.R"), regrade_write = FALSE, other_chain_dirs = character(0)))
SRL <- if (file.exists(SRLOG)) readRDS(SRLOG) else list(); FZ <- if (file.exists(file.path(CD, "finalize.json"))) rc_json_read(file.path(CD, "finalize.json")) else list()
src_b <- vapply(st79, function(x) basename(x$artifacts), "")
chk("C5 닫기 — 재채점 시행 집합에 원천 시행 5 · 기대 시행 수 = 기준 칸 1 + 걸음 2 + 원천 5 = 8 · 기대 id 에 원천 폴더 이름 · finalize.json source_trials 5",
    identical(cl, "") && all(src_b %in% basename(gsub("\\\\", "/", SRL$trials))) && identical(as.integer(SRL$expected$n_trials), 8L) && all(src_b %in% unlist(SRL$expected$ids)) &&
      length(FZ$source_trials) == 5L, c(cl, length(SRL$trials), SRL$expected$n_trials))

## ═══ Z. 실제 파일 무접촉 ═══════════════════════════════════════════════════════════
REAL1 <- vapply(REAL, md5, ""); names(REAL1) <- REAL
chk("Z1 실제 등록부 · 판 표식 원장 · 결과 원장 · 생성기 등록부 · RELEASES · P1S01 · P1S02 원장 · P1R03 사전등록 · FC 엔진 · own_spec · 진단 파일 · GPU 임대 md5 불변",
    identical(REAL0, REAL1), REAL[REAL0 != REAL1])
shtxt <- unlist(lapply(SHARED, function(f) if (file.exists(f)) readLines(f, encoding = "UTF-8", warn = FALSE) else character(0)))
chk("Z2 실제 판단 원장 · 결정 기록부에 이 시험의 표식 없음(P1S9[1-5]_ · P1S8[5-9]_ · P1R9[3-8]_ · P4C7[89]_ · TEST-LOWRISK)",
    !any(grepl("P1S9[1-5]_v|P1S8[5-9]_v|P1R9[3-8]_v|P4C7[89]_v4|TEST-LOWRISK", shtxt)))
Sys.unsetenv(c("RC_SA_ROOT", "RC_RXG_PATH"))
cat(sprintf("\n== test_round_core_v4: %d ok · %d FAIL · %.0f초 ==\n", PASS, FAIL, as.numeric(difftime(Sys.time(), T00, units = "secs"))))
cat(sprintf('{"test":"round_core_v4","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL) 1L else 0L)
