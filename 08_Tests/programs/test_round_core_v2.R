## test_round_core_v2.R — round_core v2(2026-11-11) 시험: 출시 불변 · 판 라우팅 · 알려진 답 2건(v1 = 틀린 답이 나와야 정답 · v2 = 바른 답) ·
##   부호 층 간접 호출(P1S01 격리 점검 R-2) · GPU 관문(S-2) · v1 동일 대조(실데이터 읽기 전용).
##   왜: 판단 T1 C-20261111-001(기저 풀이 상설 칸을 엔진 경로로 합친다) · 철학 C-20261111-016 → 도훈 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111 = (나)
##       (기저 자격 = 상설 판 통과만) · 판단 J-20261111-010(파일럿은 v2 위 · 같은 사례가 v1 에서는 실패해야 정답).
##   격리: 임시 폴더(SB)만 쓴다 — 임시 등록부 · 임시 상설 원장(rc_standing_append · 판 맥락은 최소 목록) · 임시 판 표식 원장 · 임시 GPU 임대 · 임시 레인 상태.
##     실제 등록부 · 원장 · 레인 · GPU 임대는 읽기만(마지막에 md5 대조). v1 과의 대조는 v1 코어를 자식 프로세스에 적재해 같은 입력으로 낸다.
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/programs/test_round_core_v2.R
##   후보판 시험: RC_V2_TEST_ROUND_SH=<round.sh 후보> · RC_V2_TEST_CHAIN_TICK=<chain_tick.R 후보>(기본 = 저장소 것)
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v2/p4.R"))) stop("저장소 루트가 아니다: ", ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
suppressMessages(source("04_Research/programs/_lib/round_core/v2/load.R"))
chk("A0 v2 적재 — RC_VERSION = v2 · RC_DIR = v2 디렉터리", identical(RC_VERSION, "v2") && grepl("/round_core/v2$", RC_DIR))
suppressPackageStartupMessages(library(data.table))
CR <- file.path(ROOT, "04_Research/programs/_lib/round_core")
SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_v2")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
if (startsWith(tolower(SB), tolower(paste0(ROOT, "/")))) stop("임시 폴더가 저장소 안이다 — 중단")
md5 <- function(p) unname(as.character(tools::md5sum(p)))
REAL <- c("06_Registry/research_programs.json", "06_Registry/q_judgment_ledger.json", "06_Registry/decision_register.json",
          "06_Registry/factor_db_vintage.json", "stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/standing_ledger.jsonl",
          ".cache/gpu_lease.json")
REAL0 <- vapply(REAL, function(f) if (file.exists(f)) md5(f) else "absent", "")

## 자식 프로세스 — 판 ver 의 코어를 적재하고 식을 평가해 .res 를 RDS 로 돌려준다(한 프로세스 = 판 하나)
run_core <- function(ver, lines, tag) {
  f <- file.path(SB, paste0("child_", tag, ".R")); o <- file.path(SB, paste0("child_", tag, ".rds"))
  writeLines(c(sprintf('setwd("%s"); suppressMessages(source("04_Research/programs/_lib/round_core/%s/load.R"))', ROOT, ver),
               sprintf('stopifnot(identical(RC_VERSION, "%s")); suppressPackageStartupMessages(library(data.table))', ver),
               lines, sprintf('saveRDS(.res, "%s")', o)), f, useBytes = TRUE)
  out <- suppressWarnings(system2("Rscript", shQuote(f), stdout = TRUE, stderr = TRUE))
  if (!file.exists(o)) { cat(tail(out, 15), sep = "\n"); stop("자식 프로세스 실패: ", tag) }
  readRDS(o)
}

## ═══ A. 출시 불변 ════════════════════════════════════════════════════════════════
REL <- rc_json_read(file.path(CR, "RELEASES.json"))
V1 <- Filter(function(r) identical(r$version, "v1"), REL$releases)[[1]]
m1 <- rc_core_manifest(file.path(CR, "v1"))
chk("A1 v1 디렉터리 매니페스트 = RELEASES v1(e70ac0af) · 파일 20개 md5 전부 같음",
    identical(m1$manifest_md5, V1$manifest_md5) && identical(sort(names(m1$files)), sort(names(V1$files))) &&
      all(vapply(names(V1$files), function(f) identical(m1$files[[f]], V1$files[[f]]), TRUE)), m1$manifest_md5)
m2 <- rc_core_manifest()
chk("A2 v2 매니페스트 ≠ v1 · 같은 파일 목록 20개 · 판 표기 v2", !identical(m2$manifest_md5, m1$manifest_md5) &&
      identical(sort(names(m2$files)), sort(names(m1$files))) && identical(m2$version, "v2"))
V2R <- Filter(function(r) identical(r$version, "v2"), REL$releases)
chk("A3 v2 출시 기록(있으면) = 지금 v2 디렉터리 매니페스트", !length(V2R) || identical(V2R[[1]]$manifest_md5, m2$manifest_md5),
    if (length(V2R)) c(V2R[[1]]$manifest_md5, "≠", m2$manifest_md5) else "")
chk("A4 생성 함수 핀(rc_p1_cell_spec · 선례 · 정본 고정 축) = P1S01 등록본 — v1 판정 경로의 생성 함수와 같은 함수",
    !length(rc_standing_pin_diff(rc_json_read("04_Research/programs/P1_RETURN/P1S01_standing_qualification/prereg.json")$spec$standing_cfg$generator_pin,
                                 rc_standing_generator_pin(ROOT))))

## ═══ R. 판 라우팅 ══════════════════════════════════════════════════════════════
RSH <- Sys.getenv("RC_V2_TEST_ROUND_SH", file.path(CR, "round.sh"))
fn_txt <- { L <- readLines(RSH, encoding = "UTF-8", warn = FALSE); a <- grep("^rc_core_of\\(\\) \\{", L); b <- which(L == "}" & seq_along(L) > a)[1]
            if (length(a) == 1L && !is.na(b)) paste(L[a:b], collapse = "\n") else "" }
chk("R0 round.sh 에 라우팅 함수 rc_core_of 가 있다", nzchar(fn_txt))
RR <- file.path(SB, "route"); for (d in c("rv1", "rv2", "rnone", "cv2")) dir.create(file.path(RR, d), recursive = TRUE, showWarnings = FALSE)
writeLines('{"schema":"round_spec_v1","core_version":"v1"}', file.path(RR, "rv1/round_spec.json"))
writeLines('{"schema":"round_spec_v1","core_version": "v2"}', file.path(RR, "rv2/round_spec.json"))
writeLines('{"schema":"round_spec_v1"}', file.path(RR, "rnone/round_spec.json"))
writeLines('{"schema":"rc_p4_chain_v1","core_version":"v2"}', file.path(RR, "cv2/chain_spec.json"))
dir.create(file.path(RR, "04_Research/programs/_lib/round_core"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(CR, "RELEASES.json"), file.path(RR, "04_Research/programs/_lib/round_core/RELEASES.json")))
route <- function(rd, def = "") {
  sh <- file.path(SB, "route.sh"); writeLines(c(sprintf('ROOT="%s"; RD="%s"', RR, rd), if (nzchar(def)) sprintf('export RC_CORE_DEFAULT=%s', def), fn_txt, "rc_core_of"), sh)
  trimws(suppressWarnings(system2(qv_bash(), shQuote(sh), stdout = TRUE, stderr = FALSE))[1])
}
lastrel <- tail(vapply(REL$releases, function(r) r$version, ""), 1)
chk("R1 사양 core_version = v1 → v1 · v2 → v2(공백 허용) · 표식 없는 사양 → v1 · 사슬 사양 v2 → v2",
    identical(route("rv1"), "v1") && identical(route("rv2"), "v2") && identical(route("rnone"), "v1") && identical(route("cv2"), "v2"),
    c(route("rv1"), route("rv2"), route("rnone"), route("cv2")))
chk("R2 사양 없는 호출('-' · 없는 폴더) = RELEASES 마지막 출시 판 · RC_CORE_DEFAULT 가 이긴다",
    identical(route("-"), lastrel) && identical(route("nosuch"), lastrel) && identical(route("-", "v1"), "v1"), c(route("-"), lastrel))
CT <- Sys.getenv("RC_V2_TEST_CHAIN_TICK", file.path(ROOT, "02_Infrastructure/programs/chain_tick.R"))
CTE <- new.env(parent = globalenv()); sys.source(CT, envir = CTE, keep.source = FALSE)
chk("R3 chain_tick.R .ct_core_version — 사슬 사양 v2 → v2 · 표식 없는 사양 → v1 · 사슬 없음 → 마지막 출시 판(코드 루트의 RELEASES)",
    is.function(CTE$.ct_core_version) && identical(CTE$.ct_core_version(file.path(RR, "cv2"), RR, ROOT), "v2") &&
      identical(CTE$.ct_core_version(file.path(RR, "rnone"), RR, ROOT), "v1") && identical(CTE$.ct_core_version(NULL, RR, ROOT), lastrel))
chk("R4 chain_tick.R 에 v1 고정 경로가 남지 않았다(적재 · 상수 판독)", !any(grepl("round_core/v1/", readLines(CT, encoding = "UTF-8", warn = FALSE), fixed = TRUE)))
chk("R5 v2 CLI(driver · standing · measure_cell)는 v2 load.R 을 적재한다 — v1 경로 0",
    !any(grepl("round_core/v1", unlist(lapply(c("driver.R", "standing.R", "measure_cell.R", "load.R"), function(f) readLines(file.path(RC_DIR, f), encoding = "UTF-8", warn = FALSE))), fixed = TRUE)))

## ═══ 공통 픽스처 — 엔진 3 · 칸 사양 · 상설 원장 · 등록부 · 레인 산출 ═════════════════════════
mk_engine <- function(nm, torch = FALSE) {
  d <- file.path(SB, "strategies", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("## 시험 엔진(v2) — 실행하지 않는다", "PORTFOLIO <- NULL", if (torch) 'writeLines("import torch", "x.py")', strrep("# 채움\n", 30)), file.path(d, "engine.R"))
  file.path(d, "engine.R")
}
ENG1 <- mk_engine("RP_AUTO_T1"); ENG2 <- mk_engine("RP_AUTO_T2"); ENG3 <- mk_engine("RP_AUTO_T3")
paper <- function(k) list(url = paste0("https://arxiv.org/abs/", k), title = paste("Test paper", k), paper_key = k)
spec_std <- function(code, eng, k) rc_p1_cell_spec(code, eng, paper(k), k, 1L, "v2 시험 시드", root = ROOT)
dir.create(file.path(SB, "specs"), showWarnings = FALSE)
wspec <- function(s, nm) { p <- file.path(SB, "specs", paste0(nm, ".json")); rc_json_write(s, p); p }
S1_E2 <- wspec(spec_std("T1_E2", ENG1, "2001.00001"), "T1_E2")
s3 <- spec_std("T1_E3", ENG1, "2001.00001"); s3$factors <- list(list(kind = "db", id = "M01_Mom_12_1"))
s3$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy"); s3$rebalance <- list(kind = "rank_buffer", mult = 2, label = "buffer_2x")
S1_E3 <- wspec(s3, "T1_E3")
S3_E2 <- wspec(spec_std("T3_E2", ENG3, "2001.00003"), "T3_E2")
mk_lane <- function(nm, grade) { d <- file.path(SB, "art", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  rc_json_write(list(run_id = "RP_20261111_090000_t", essence_grade = grade, grade_scheme = "grade_v3"), file.path(d, "authoritative_remeasure.json")); d }
LA1 <- mk_lane("lane_T1", "C"); LA2 <- mk_lane("lane_T2", "B"); LA3 <- mk_lane("lane_T3", "C")
SA1_E2 <- mk_lane("std_T1_E2", "C"); SA1_E3 <- mk_lane("std_T1_E3", "C"); SA3_E2 <- mk_lane("std_T3_E2", "C")
FDVL <- file.path(SB, "factor_db_vintage.json")
rc_json_write(list(schema = "factor_db_vintage_v1", entries = list(list(id = "REPAIR-T", completed_at = "2026-11-10T01:00:00+09:00", scope = "all"))), FDVL)
item <- function(key, eng, art, pk) list(key = key, kind = "engine", engine_path = eng, artifacts = art, has_short = FALSE, implementation_suspect = FALSE,
                                         holdings_claim_mismatch = FALSE, audit_verdict = "faithful", paper_key = pk, title = paste("Test paper", pk), enqueued_at = "2026-11-11T09:00:00+0900")
REG <- file.path(SB, "research_programs.json")
rc_json_write(list(schema = "research_programs_v1", programs = list(list(id = "P1_RETURN", status = "ready", queue = list(),
  consumed = list(item("engine:T1", ENG1, LA1, "2001.00001"), item("engine:T2", ENG2, LA2, "2001.00002"), item("engine:T3", ENG3, LA3, "2001.00003"))))), REG)
SA <- file.path(SB, "sa"); RID <- "P1S99_v2test"
LEDGER <- file.path(SA, "stage_artifacts/programs/P1_RETURN", RID, "standing_ledger.jsonl")
CTX <- list(ledger = LEDGER, spec = list(round_id = RID), cfg = list(edition = 1L), prereg_md5 = "v2test")
seed <- function(code, eng, sp, k) rc_standing_append(CTX, list(event = "enqueue", code = code, engine = code, role = "reference", source = "seed",
  engine_path = eng, engine_md5 = md5(eng), cell_spec = sp, cell_spec_md5 = md5(sp), paper = paper(k), family_root = k, n_family = 1L))
meas <- function(code, art) rc_standing_append(CTX, list(event = "measure", code = code, ok = TRUE, fp_same = TRUE, artifacts = art))
verd <- function(code, q) rc_standing_append(CTX, list(event = "verdict", code = code, qualify = q, visible = list(uc_vis = 0.70)))
invisible({ seed("P1S99_T1_E2", ENG1, S1_E2, "2001.00001"); meas("P1S99_T1_E2", SA1_E2); verd("P1S99_T1_E2", FALSE)     # 사례 1: 맨 엔진 칸 미달
            seed("P1S99_T1_E3", ENG1, S1_E3, "2001.00001"); meas("P1S99_T1_E3", SA1_E3); verd("P1S99_T1_E3", TRUE)      #         처치 칸만 통과
            seed("P1S99_T3_E2", ENG3, S3_E2, "2001.00003"); meas("P1S99_T3_E2", SA3_E2); verd("P1S99_T3_E2", TRUE) })   # 대조: 표준 칸 통과
chk("F0 임시 상설 원장 사슬 정상(9줄)", isTRUE(rc_standing_ledger_verify(LEDGER)$ok) && rc_standing_ledger_verify(LEDGER)$n == 9L)

## ═══ C. 구성 판독 · 기저 풀 — 알려진 답 2건(v1 = 틀린 답 · v2 = 바른 답) + 대조 ═══════════════════════
Q2 <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SA)[round_id == RID]
chk("C1 상설 통과 칸 = T1_E3 · T3_E2 둘(미달 T1_E2 없음) · 구성 판독: T1_E3 = treatment(factors · weighting · rebalance) · T3_E2 = standard",
    setequal(Q2$code, c("P1S99_T1_E3", "P1S99_T3_E2")) && identical(Q2[code == "P1S99_T1_E3"]$construction, "treatment") &&
      setequal(strsplit(Q2[code == "P1S99_T1_E3"]$treatment_axes, ",")[[1]], c("factors", "weighting", "rebalance")) &&
      identical(Q2[code == "P1S99_T3_E2"]$construction, "standard"), paste(Q2$code, Q2$construction, Q2$treatment_axes))
cs_bad <- rc_standing_construction(S1_E3, "0000", ROOT)
chk("C2 칸 사양 md5 ≠ 원장 · 사양 없음 = 구성 NA(fail-closed)", is.na(cs_bad$construction) && is.na(rc_standing_construction(file.path(SB, "nope.json"), NA, ROOT)$construction))
P2 <- rc_p4_base_pool(ROOT, registry_path = REG, standing = Q2, fdv_ledger_path = FDVL)
P1 <- run_core("v1", c(sprintf('Q <- rc_standing_qualified("P1_RETURN", root = "%s", sa_root = "%s")[round_id == "%s"]', ROOT, SA, RID),
                       sprintf('.res <- list(Q = Q, P = rc_p4_base_pool("%s", registry_path = "%s", standing = Q, fdv_ledger_path = "%s"))', ROOT, REG, FDVL)), "pool_v1")
p1 <- P1$P; row <- function(P, k) P[key == k]
## 사례 1 — 같은 엔진 경로 두 칸 중 처치 칸만 통과: 맨 엔진 행(engine:T1)은 자격이 없어야 한다
chk("C3 사례 1 · v1 = 틀린 답(대조) — 처치 칸 T1_E3 이 맨 엔진 행 engine:T1 에 합쳐져 자격 TRUE(C-20261111-001 재현)",
    isTRUE(row(p1, "engine:T1")$eligible) && identical(row(p1, "engine:T1")$standing_code, "P1S99_T1_E3"), paste(row(p1, "engine:T1")$reason))
chk("C4 사례 1 · v2 = 바른 답 — engine:T1 자격 없음(not_qualified) · 처치 칸은 따로(standing:P1S99_v2test:P1S99_T1_E3 · treatment · 자격 TRUE)",
    identical(row(P2, "engine:T1")$eligible, FALSE) && grepl("not_qualified", row(P2, "engine:T1")$reason) &&
      isTRUE(row(P2, paste0("standing:", RID, ":P1S99_T1_E3"))$eligible) && identical(row(P2, paste0("standing:", RID, ":P1S99_T1_E3"))$construction, "treatment"),
    paste(P2$key, P2$eligible, P2$reason))
## 사례 2 — 등급 경로: 전 기간 권위 등급 B · 상설 통과 없음 → 자격이 없어야 한다(결정 (나))
chk("C5 사례 2 · v1 = 틀린 답(대조) — engine:T2 권위 등급 B 만으로 자격 TRUE(등급 경로)", isTRUE(row(p1, "engine:T2")$eligible) && identical(row(p1, "engine:T2")$grade, "B"),
    paste(row(p1, "engine:T2")$reason))
chk("C6 사례 2 · v2 = 바른 답 — engine:T2 자격 없음(not_qualified) · 등급 B 는 참고 열로 남는다",
    identical(row(P2, "engine:T2")$eligible, FALSE) && grepl("not_qualified", row(P2, "engine:T2")$reason) && identical(row(P2, "engine:T2")$grade, "B"))
## 대조 — 표준 구성 칸 통과는 v1 · v2 모두 같은 엔진 행에 합쳐 자격(동작 보존)
chk("C7 대조 · 표준 칸 T3_E2 통과 = v1 · v2 모두 engine:T3 에 합쳐 자격 TRUE · v2 구성 standard",
    isTRUE(row(p1, "engine:T3")$eligible) && isTRUE(row(P2, "engine:T3")$eligible) && identical(row(P2, "engine:T3")$standing_code, "P1S99_T3_E2") &&
      identical(row(P2, "engine:T3")$construction, "standard") && !nrow(row(P2, paste0("standing:", RID, ":P1S99_T3_E2"))))
chk("C8 처치 행은 같은 엔진 등록부 행의 레인 꼬리표를 이어받는다(구현 의심 등록부 → 처치 행도 implementation_suspect)", {
  r2 <- rc_json_read(REG); r2$programs[[1]]$consumed[[1]]$implementation_suspect <- TRUE; REG2 <- file.path(SB, "reg_suspect.json"); rc_json_write(r2, REG2)
  P2s <- rc_p4_base_pool(ROOT, registry_path = REG2, standing = Q2, fdv_ledger_path = FDVL)
  identical(row(P2s, paste0("standing:", RID, ":P1S99_T1_E3"))$eligible, FALSE) && grepl("implementation_suspect", row(P2s, paste0("standing:", RID, ":P1S99_T1_E3"))$reason) })
chk("C9 구판 자격 표(construction 열 없음)를 넘기면 상설 행은 construction_unknown(자격 없음 · fail-closed)", {
  Qold <- copy(Q2)[, c("construction", "treatment_axes", "construction_why", "cell_spec", "cell_spec_md5") := NULL]
  Po <- rc_p4_base_pool(ROOT, registry_path = REG, standing = Qold, fdv_ledger_path = FDVL)
  all(grepl("construction_unknown", Po[!is.na(standing_code)]$reason)) && !any(Po[!is.na(standing_code)]$eligible) })
chk("C10 풀 md5 가 standing_code · construction 을 덮는다(같은 표 = 같은 md5 · 구성만 바꾸면 달라진다)", {
  a <- rc_p4_pool_md5(P2); b <- rc_p4_pool_md5(copy(P2)); P2x <- copy(P2); P2x[key == "engine:T3", construction := "treatment"]
  identical(a, b) && !identical(a, rc_p4_pool_md5(P2x)) })
## 기저 칸 사양 — 처치 행 = 통과 칸 사양 그대로 · 표준 행 = v1 과 바이트 같은 사양
TB <- file.path(SB, "base_T1_E3.json"); kT <- paste0("standing:", RID, ":P1S99_T1_E3")
e_tb <- err_of(rc_p4_base_cell_spec(kT, P2, ROOT, TB)); tb <- if (file.exists(TB)) rc_json_read(TB) else list()
chk("C11 처치 행 기저 칸 사양 = 통과 칸 사양의 처치 축 그대로(factors · weighting · rebalance) · same_construction TRUE · 코드 꼬리 _T<칸 md5 6>",
    !nzchar(e_tb) && length(tb$factors) == 1L && identical(tb$weighting$kind, "catalog") && identical(tb$rebalance$kind, "rank_buffer") &&
      isTRUE(tb$p4$same_construction) && identical(tb$p4$construction, "treatment") && grepl(paste0("_T", substr(md5(S1_E3), 1, 6), "$"), tb$code) &&
      identical(tb$selection_accounting$lineage, "P4_chain_base") && length(rc_p4_spec_diff(s3, tb, "base", ROOT)$changed) == 0L, e_tb)
chk("C12 처치 행 — 통과 칸 사양이 원장 md5 와 다르면 기저 칸을 만들지 않는다(R2)", {
  P2m <- copy(P2); P2m[key == kT, standing_cell_spec_md5 := "0000"]; grepl("md5", err_of(rc_p4_base_cell_spec(kT, P2m, ROOT, file.path(SB, "x.json")))) })
SB2 <- file.path(SB, "base_T3_v2.json"); invisible(rc_p4_base_cell_spec("engine:T3", P2, ROOT, SB2))
B1 <- run_core("v1", c(sprintf('Q <- rc_standing_qualified("P1_RETURN", root = "%s", sa_root = "%s")[round_id == "%s"]', ROOT, SA, RID),
                       sprintf('P <- rc_p4_base_pool("%s", registry_path = "%s", standing = Q, fdv_ledger_path = "%s")', ROOT, REG, FDVL),
                       sprintf('rc_p4_base_cell_spec("engine:T3", P, "%s", "%s/base_T3_v1.json"); .res <- TRUE', ROOT, SB)), "spec_v1")
chk("C13 대조 · 표준 행 기저 칸 사양 = v1 과 바이트 같다(engine:T3)", file.exists(file.path(SB, "base_T3_v1.json")) && identical(md5(SB2), md5(file.path(SB, "base_T3_v1.json"))))

## ═══ S. 부호 층 간접 호출(R-2) — v2 는 8형태 모두 잡고 v1 은 간접 4형태를 놓친다 · 음성 대조 3 ═══════════════
PR <- file.path(SB, "probes"); dir.create(PR, showWarnings = FALSE)
probes <- list(
  direct = "x <- align_factor_direction(f, d)", dollar = "x <- E$align_factor_direction(f)", dcolon = "x <- qm::compute_rolling_ic_all(f)",
  direct2 = "y <- compute_rolling_ic_all(r, 12)",
  fvalue = "x <- lapply(fs, align_factor_direction)", docall = "x <- do.call('align_factor_direction', list(f))",
  matchfun = "g <- match.fun(\"compute_rolling_ic_all\"); y <- g(f)", alias = "af <- align_factor_direction\nx <- af(f)")
negs <- list(comment = "# align_factor_direction 은 쓰지 않는다\nx <- 1", message = "message('align_factor_direction 쓰지 않음')\nx <- 1",
             argname = "z <- list(align_factor_direction = 1)")
wprobe <- function(nm, body) { p <- file.path(PR, paste0(nm, ".R")); writeLines(c(body, "PORTFOLIO <- data.frame()"), p); p }
pf <- vapply(names(probes), function(n) wprobe(n, probes[[n]]), ""); nf <- vapply(names(negs), function(n) wprobe(n, negs[[n]]), "")
o2 <- vapply(c(pf, nf), function(p) rc_standing_static(p)$orientation, "")
o1 <- run_core("v1", sprintf('.res <- vapply(c(%s), function(p) rc_standing_static(p)$orientation, "")', paste(sprintf('"%s"', c(pf, nf)), collapse = ", ")), "probe_v1")
chk("S1 v2 — 부호 층 8형태(직접 · $ · :: · 함수 값 · do.call · match.fun · 별칭) 전부 orientation_layer", all(o2[seq_along(pf)] == "orientation_layer"), o2)
chk("S2 v2 — 음성 대조(주석 · 다른 문자열 · 인자 이름)는 orientation_layer 아님", !any(o2[length(pf) + seq_along(nf)] == "orientation_layer"), o2[length(pf) + seq_along(nf)])
chk("S3 v1 = 대조 — 직접 4형태는 잡고 간접 4형태(함수 값 · do.call · match.fun · 별칭)는 놓친다(점검 R-2 재현)",
    all(o1[1:4] == "orientation_layer") && !any(o1[5:8] == "orientation_layer"), o1)

## ═══ G. GPU 관문(S-2) — 임시 레인 상태 · 임시 GPU 임대(실제 임대 · 레인 무접촉) ═════════════════════════
GS <- file.path(SB, "gpu"); dir.create(file.path(GS, "state"), recursive = TRUE); dir.create(file.path(GS, "slots"))
Sys.setenv(QVEST_GPU_LEASE = file.path(GS, "gpu_lease.json"), QVEST_RP_STATE_DIR = file.path(GS, "state"), QVEST_RP_SLOT_DIR = file.path(GS, "slots"),
           QVEST_RP_CLAIM = file.path(GS, "state/rf_replication.claim"), QVEST_RP_REQUEST = file.path(GS, "slots/replication_request.json"))
ENGG <- mk_engine("RP_AUTO_TG", torch = TRUE)
g_cpu <- rc_gpu_guard(ENG1, "rc_v2test:cpu", root = ROOT)
chk("G1 cpu 엔진 = 그대로 잰다(임대 없음 · 임대 파일 안 생김)", isTRUE(g_cpu$ok) && identical(g_cpu$state, "cpu") && !file.exists(Sys.getenv("QVEST_GPU_LEASE")), g_cpu$state)
g1 <- rc_gpu_guard(ENGG, "rc_v2test:gpu", root = ROOT)
ls1 <- tryCatch(rc_json_read(Sys.getenv("QVEST_GPU_LEASE")), error = function(e) list())
chk("G2 gpu 엔진(torch) · 레인 측정 0 = 임대를 잡는다(임시 임대 파일 · 보유자 = 이 측정)", isTRUE(g1$ok) && identical(g1$state, "acquired") && identical(ls1$holder, "rc_v2test:gpu"),
    paste(g1$state, g1$reason))
g1b <- rc_gpu_guard(ENGG, "rc_v2test:other", root = ROOT)
chk("G3 다른 보유자가 임대 중 = 재지 않는다(lease_held · ok FALSE)", identical(g1b$ok, FALSE) && identical(g1b$state, "lease_held"), paste(g1b$state, g1b$reason))
g1$release(); ls2 <- tryCatch(rc_json_read(Sys.getenv("QVEST_GPU_LEASE")), error = function(e) list())
chk("G4 놓기 = 임대 풀림(보유자 없음)", !identical(ls2$holder, "rc_v2test:gpu"), ls2$holder %||% "")
Sys.setenv(QVEST_RP_STATE_DIR = file.path(GS, "nostate", "x"), QVEST_RF_CONFIG = file.path(GS, "broken.json")); writeLines("{", file.path(GS, "broken.json"))
gx <- rc_gpu_guard(ENGG, "rc_v2test:x", root = file.path(SB, "no_root"))
chk("G5 판별 · 상태 판독 불가 = 재지 않는다(check_error · fail-closed)", identical(gx$ok, FALSE) && identical(gx$state, "check_error"), paste(gx$state, gx$reason))
Sys.unsetenv(c("QVEST_GPU_LEASE", "QVEST_RP_STATE_DIR", "QVEST_RP_SLOT_DIR", "QVEST_RP_CLAIM", "QVEST_RP_REQUEST", "QVEST_RF_CONFIG"))

## ═══ V. v1 동일 대조(실데이터 읽기 전용) — 바뀐 곳 = 결정 (나) 행뿐 ════════════════════════════════
PV2 <- rc_p4_base_pool(); Pv <- run_core("v1", '.res <- rc_p4_base_pool()', "realpool_v1")
cm <- setdiff(intersect(names(Pv), names(PV2)), "reason"); setkey(PV2, key); setkey(Pv, key)
same_cols <- all(vapply(cm, function(k) identical(PV2[[k]], Pv[[k]]), TRUE))
dif <- PV2$reason != Pv$reason
chk("V1 실제 기저 풀 — v1 과 공통 열(reason 밖) 전부 같음 · reason 이 다른 행은 권위 등급 A/B 행뿐이고 v2 는 not_qualified 를 더했다(결정 (나))",
    same_cols && identical(PV2$key, Pv$key) && all(PV2$grade[dif] %in% c("A", "B")) && all(grepl("not_qualified", PV2$reason[dif])) &&
      all(grepl("not_qualified", PV2$reason[PV2$grade %in% c("A", "B") & !PV2$standing_qualified])),
    sprintf("행 %d · reason 다른 행 %d", nrow(PV2), sum(dif)))
lane_fs <- Sys.glob("04_Research/strategies/RP_AUTO_*/engine.R")
st2 <- vapply(lane_fs, function(f) { s <- rc_standing_static(f); paste(s$orientation, paste(sort(s$orientation_tokens), collapse = ","), paste(s$outputs, collapse = ",")) }, "")
st1 <- run_core("v1", c(sprintf('fs <- c(%s)', paste(sprintf('"%s"', lane_fs), collapse = ", ")),
                        '.res <- vapply(fs, function(f) { s <- rc_standing_static(f); paste(s$orientation, paste(sort(s$orientation_tokens), collapse = ","), paste(s$outputs, collapse = ",")) }, "")'), "lane_v1")
chk(sprintf("V2 레인 엔진 %d개 정적 판정(방향 층 · 토큰 · 산출 대입) — v1 과 전부 같다", length(lane_fs)), identical(unname(st1), unname(st2)), sum(st1 != st2))
pre <- rc_json_read("04_Research/programs/P1_RETURN/P1S01_standing_qualification/prereg.json")
sn2 <- rc_rules_sentences(rc_rules_resolve(pre$spec$rules, ROOT))
sn1 <- run_core("v1", '.res <- rc_rules_sentences(rc_rules_resolve(rc_json_read("04_Research/programs/P1_RETURN/P1S01_standing_qualification/prereg.json")$spec$rules, rc_root()))', "rules_v1")
chk("V3 P1S01 판정 규칙 문장 — v1 · v2 같은 문장 · 등록본 문장과 같다", identical(sn1, sn2) && identical(unlist(pre$sentences), sn2))

## ═══ 실제 원장 무접촉 ═══════════════════════════════════════════════════════════
REAL1 <- vapply(REAL, function(f) if (file.exists(f)) md5(f) else "absent", "")
chk("Z1 실제 등록부 · 판단 원장 · 결정 기록부 · 판 표식 원장 · P1S01 원장 · GPU 임대 md5 불변", identical(REAL0, REAL1), names(REAL)[REAL0 != REAL1])
cat(sprintf("\n== test_round_core_v2: %d ok · %d FAIL ==\n", PASS, FAIL))
quit(status = if (FAIL) 1L else 0L)
