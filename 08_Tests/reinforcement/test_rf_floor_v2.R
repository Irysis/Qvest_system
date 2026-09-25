#!/usr/bin/env Rscript
#==============================================================================
# test_rf_floor_v2.R — floor v2 정의 계약(rf_floor_v2.R · 플랜 P2-03) 양방향 검사
#
# 재는 것
#   D  결정론 — 같은 입력으로 두 번 생성하면 문서가 같다(생성 시각 제외)
#   C  인용 충실도 — 문서의 인용 칸 = 원장 attempt 필드(essence·grade·measurement_regime·vintage_flags·adversary verdict)
#      / 돌연변이: 문서 수치 +0.001 · 등급 변경 · 표식 삭제 → 검사기가 잡는다
#   A  as-of 방향(C14) — F1 선정 표본의 IC 가용 최대일 <= as-of · selection_basis = asof_ic · 규칙 라벨 · B1_ 코드
#   I  위반 주입(미래 IC) — as-of 뒤 IC 를 한 팩터에 크게 심으면 as-of 선정 불변 / 같은 주입을 창 안에 하면 그 팩터가 잡힌다(양성 대조) /
#      결정 시점 뒤·NA as-of 는 정본 상한 가드(R3)에서 stop
#   M  돌연변이 — rf_factor_arms.R 의 as-of 절단 줄을 무력화한 사본으로 I 를 돌리면 불변성이 깨진다(red 를 잰다)
#   E  제외 술어 — PIT 표식·exec_price·축·적대검증·미측정·Q④ 노출/판독불가 = 제외 · 비PIT 빈티지 표식 = caveat 만
#   X  Q④ 노출 검출기 — 통계 있는 절 = 노출 · 식별자(arXiv id)만 = 비노출 · 절 없음 = 비노출 · 파일 없음 = NA /
#      돌연변이: 식별자 보호식을 비우면 arXiv id 가 통계로 오판된다
#   V  적대검증 상태 = 정본 술어(rf_adversary_status) 위임 — 직접 호출과 같다 · verdict pass 주입 시 ok
#   W  쓰기 — written → already → 내용이 다르면 거부(파일 불변) · 생성 루트만 다르면 already · 정규화가 수치 차이를 가리지 않음
#   P  핀 대조 — 같은 입력 재생성 드리프트 0 / 원장 수치 변경 → 바닥·핀 드리프트 + 인용 불일치 검출
#   F  설정 fail-closed — design_exposure 부재 · seed_offset 음수 → stop
#   S  F1 스펙 구조 — 팩터 = 재선정 집합 = 설정 규칙으로 정본 선정기 직접 호출 결과 · 기저 엔진 = 계보 칸 · fixed_axes = 격자 · 오버레이 없음 · 깊이 = 계보 칸 DB 팩터 수 ·
#      '같으면' 분기 양성 대조(계보 집합 = as-of 집합이면 same_set)
#   R  읽기 전용 — 루트 지문 전후 동일
#   (적대검증 수리 2026-09-25) E11~13 기저 엔진 노출 제외 술어 · B 기저 엔진 설계 노출 검출기(합성 5종 + 보호식 돌연변이 +
#      실데이터 양성 대조 = 22632 결합 엔진 · 음성 대조 = 충실구현 엔진) · G 사전등록 관문(닫힘 · 열림 양성 대조 · open 결정 ·
#      판독 불가 fail-closed) · F3·F4 설정 fail-closed
# 부작용: 쓰기는 tempdir 픽스처뿐(루트는 읽기 전용 원천 — 전후 md5 대조).
# 실행: QM_ROOT=<루트> Rscript --no-environ 08_Tests/reinforcement/test_rf_floor_v2.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
cat(sprintf("ROOT(읽기 전용) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && any(nzchar(why))) paste0(" — ", paste(why, collapse = " ")) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
emit <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"rf_floor_v2","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
}
TMP <- normalizePath(tempdir(), winslash = "/")
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)),
                                    tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(TMP, ROOT)) { ng("tempdir 가 루트 안에 있다 — 쓰기 위험(중단)", TMP); emit(); quit(status = 1L) }

# ── 루트 지문(전후 대조) ──
PROD <- file.path(ROOT, c("06_Registry/reinforce_ledger_l1.json", "06_Registry/reinforce_ledger_l2.json", "06_Registry/reinforce_program.json",
                          "06_Registry/factor_evidence.json", ".cache/factor_db/factor_ic_monthly.parquet", "06_Registry/pit_quarantine.json"))
md5_prod <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
PROD0 <- md5_prod()
PRE0 <- sort(list.files(file.path(ROOT, "06_Registry/prereg")))

# ── 픽스처 = 루트 필요 파일 사본(tempdir) ──
FX <- file.path(TMP, "rfv_fx"); unlink(FX, recursive = TRUE)
cp <- function(rel, dst_root = FX) {
  src <- file.path(ROOT, rel); if (!file.exists(src)) return(FALSE)
  dir.create(dirname(file.path(dst_root, rel)), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, file.path(dst_root, rel), overwrite = TRUE)
}
need <- c("06_Registry/reinforce_ledger_l1.json", "06_Registry/reinforce_ledger_l2.json", "06_Registry/reinforce_program.json",
          "06_Registry/factor_evidence.json", "06_Registry/factor_panel_axis.json", "06_Registry/pit_quarantine.json",
          "06_Registry/decision_register.json",
          "06_Registry/prereg/reference_floors_v2.config.json",
          ".cache/factor_db/factor_ic_monthly.parquet", ".cache/factor_db/factor_registry.json",
          "02_Infrastructure/ops/rf_factor_arms.R", "02_Infrastructure/validation/pit_quarantine.R",
          "02_Infrastructure/portfolio/weight_catalog.R",
          file.path("02_Infrastructure/reinforcement", list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "\\.R$")),
          file.path(".cache/rf_b1_design", list.files(file.path(ROOT, ".cache/rf_b1_design"), pattern = "\\.(json|materials\\.txt)$")))
okc <- vapply(need, cp, logical(1))
miss <- need[!okc & !grepl("^\\.cache/rf_b1_design/", need)]
if (length(miss)) { ng("픽스처 사본 실패", paste(head(miss, 5), collapse = ", ")); emit(); quit(status = 1L) }
OLD_QM <- Sys.getenv("QM_ROOT"); Sys.setenv(QM_ROOT = FX)   # 정본 계약이 적재 시 QM_ROOT 를 본다 — 픽스처로 격리
on.exit(Sys.setenv(QM_ROOT = OLD_QM), add = TRUE)
invisible(capture.output(source(file.path(FX, "02_Infrastructure/reinforcement/rf_floor_v2.R"), encoding = "UTF-8")))
EN <- rfv_env(FX)
CFGP <- file.path(FX, "06_Registry/prereg/reference_floors_v2.config.json")

# ═══ D 결정론 ═══
cat("\n[D] 결정론\n")
d1 <- rfv_build(FX, CFGP, FX, EN); d2 <- rfv_build(FX, CFGP, FX, EN)
dd <- rfv_diff(.rfv_strip(d1), .rfv_strip(d2))
chk(!length(dd), "D1 같은 입력 두 번 생성 = 같은 문서(생성 시각 제외)", head(dd, 3))
chk(identical(d1$floors$F1$reselect$picked_ids, d2$floors$F1$reselect$picked_ids) && length(d1$floors$F1$reselect$picked_ids) >= 1L,
    "D2 F1 집합 재현")

# ═══ C 인용 충실도 ═══
cat("\n[C] 인용 충실도\n")
chk(!length(rfv_check_citations(d1, FX)), "C1 인용 칸 = 원장 필드(F2·F3·계보 칸)", rfv_check_citations(d1, FX))
m <- d1; m$floors$F3_DNN$cite$essence$calmar <- as.numeric(m$floors$F3_DNN$cite$essence$calmar) + 0.001
chk("F3_DNN:essence" %in% rfv_check_citations(m, FX), "C2 돌연변이(수치 +0.001) 검출")
m <- d1; m$floors$F2$cite$grade <- "A"
chk("F2:grade" %in% rfv_check_citations(m, FX), "C3 돌연변이(등급 변경) 검출")
m <- d1; m$lineage_reference$cite$vintage_flags <- list()
chk("lineage:vintage_flags" %in% rfv_check_citations(m, FX), "C4 돌연변이(표식 삭제) 검출")
m <- d1; m$floors$F2$cite$adversary$ledger_verdict <- "pass"
chk("F2:adversary_verdict" %in% rfv_check_citations(m, FX), "C5 돌연변이(적대검증 verdict 위조) 검출")

# ═══ A as-of 방향 ═══
cat("\n[A] as-of 방향(C14)\n")
PL <- d1$floors$F1$reselect$pool
chk(identical(PL$selection_basis, "asof_ic"), "A1 선정 기저 = asof_ic", PL$selection_basis)
chk(!is.na(PL$ic_max_usable) && as.Date(PL$ic_max_usable) <= as.Date(PL$asof), "A2 IC 가용 최대일 <= as-of", paste(PL$ic_max_usable, PL$asof))
SP <- d1$floors$F1$spec
chk(identical(SP$selection_basis, "asof_ic") && identical(as.character(SP$selection_asof), as.character(PL$asof)), "A3 스펙 selection_basis/asof 부기")
chk(grepl(RFV_RULE_LABEL_RE, SP$label) && startsWith(SP$code, "B1_"), "A4 규칙 라벨·B1_ 코드(P0-14 as-of 증명 조건)", paste(SP$code, SP$label))

# ═══ I 위반 주입(미래 IC) ═══
cat("\n[I] 위반 주입 — as-of 뒤 IC\n")
F1ids <- d1$floors$F1$reselect$picked_ids
LIN <- d1$lineage_reference$cite$factors
DEP <- length(LIN); OFF <- as.integer(d1$floors$F1$selection_path$seed_rule$seed_offset)
P0 <- EN$rf_factor_pool(FX)
cand <- P0$pool[P0$pool$rankable == TRUE & !(P0$pool$id %in% c(F1ids, LIN))]
setorderv(cand, "ic_asof", 1L, na.last = TRUE)
X <- cand$id[ceiling(nrow(cand) / 2)]                     # 가운데 순위 팩터(주입 전 선정과 무관)
FX2 <- file.path(TMP, "rfv_fx2"); unlink(FX2, recursive = TRUE)
invisible(vapply(need, cp, logical(1), dst_root = FX2))
icp <- file.path(FX2, ".cache/factor_db/factor_ic_monthly.parquet")
IC <- as.data.table(read_parquet(icp, mmap = FALSE)); asofD <- as.Date(PL$asof)   # mmap=FALSE — 매핑된 파일은 Windows 에서 덮어쓸 수 없다(error 1224)
nfut <- IC[Factor_Name == X & as.Date(Usable_Date) > asofD, .N]
IC[Factor_Name == X & as.Date(Usable_Date) > asofD, IC := 0.9 + 0.05 * sin(seq_len(.N))]   # 큰 양의 IC(분산>0 — 최근 ICIR 부호 조건 통과)
tmpq <- paste0(icp, ".tmp"); write_parquet(IC, tmpq); stopifnot(file.remove(icp), file.rename(tmpq, icp))
chk(nfut > 12L, sprintf("I0 주입 대상 %s · as-of 뒤 행 %d 개 덮음", X, nfut), nfut)
s0 <- rfv_asof_reselect(FX, EN, LIN, DEP, OFF); s1 <- rfv_asof_reselect(FX2, EN, LIN, DEP, OFF)
chk(identical(s0$picked_ids, s1$picked_ids), "I1 as-of 선정 불변(미래 IC 주입에 둔감)", paste(s1$picked_ids, collapse = "+"))
chk(!(X %in% s1$picked_ids), "I2 주입 팩터가 as-of 선정에 없다")
# 양성 대조 — 같은 팩터를 **창 안**(Usable_Date <= as-of)에 심으면 as-of 선정이 그것을 잡는다(주입이 이빨이 있다 · 기계 생존)
FX4 <- file.path(TMP, "rfv_fx4"); unlink(FX4, recursive = TRUE)
invisible(vapply(need, cp, logical(1), dst_root = FX4))
icp4 <- file.path(FX4, ".cache/factor_db/factor_ic_monthly.parquet")
IC4 <- as.data.table(read_parquet(icp4, mmap = FALSE))
nin <- IC4[Factor_Name == X & as.Date(Usable_Date) <= asofD, .N]
IC4[Factor_Name == X & as.Date(Usable_Date) <= asofD, IC := 0.9 + 0.05 * sin(seq_len(.N))]
tmpq <- paste0(icp4, ".tmp"); write_parquet(IC4, tmpq); stopifnot(file.remove(icp4), file.rename(tmpq, icp4))
s4 <- rfv_asof_reselect(FX4, EN, LIN, DEP, OFF)
chk(nin >= 1L && X %in% s4$picked_ids, sprintf("I3 양성 대조 — 창 안 주입(%d행)은 as-of 선정이 잡는다", nin), paste(s4$picked_ids, collapse = "+"))
# 정본 상한 가드(R3) 생존 — 결정 시점 뒤 as-of·NA 는 계약을 통과하지 못한다(바닥 정의가 전표본으로 새지 않는다)
late <- format(asofD + 400)
e1 <- tryCatch({ rfv_asof_reselect(FX2, EN, LIN, DEP, OFF, asof = late); "no_error" }, error = function(e) "error")
chk(identical(e1, "error"), sprintf("I4 결정 시점 뒤 as-of(%s) → stop(R3 상한 가드 · 우회 없음)", late))
e2 <- tryCatch({ rfv_asof_reselect(FX2, EN, LIN, DEP, OFF, asof = NA); "no_error" }, error = function(e) "error")
chk(identical(e2, "error"), "I5 as-of NA(전표본) → stop")

# ═══ M 돌연변이 — as-of 절단 무력화 ═══
cat("\n[M] 돌연변이 — as-of 절단 무력화\n")
MX <- file.path(TMP, "rfv_mx"); unlink(MX, recursive = TRUE)
invisible(vapply(c("02_Infrastructure/ops/rf_factor_arms.R", "02_Infrastructure/validation/pit_quarantine.R",
                   "02_Infrastructure/portfolio/weight_catalog.R",
                   file.path("02_Infrastructure/reinforcement", list.files(file.path(FX, "02_Infrastructure/reinforcement"), pattern = "\\.R$"))),
                 cp, logical(1), dst_root = MX))
ap <- file.path(MX, "02_Infrastructure/ops/rf_factor_arms.R")
src <- readLines(ap, encoding = "UTF-8", warn = FALSE)
cut_line <- "    IC <- IC[!is.na(Usable_Date) & Usable_Date <= A$date]"
hit <- which(src == cut_line)
chk(length(hit) == 1L, "M0 as-of 절단 줄을 정확히 1곳 찾음(돌연변이 대상)", length(hit))
if (length(hit) == 1L) {
  src[hit] <- "    IC <- IC   # MUTANT: as-of 절단 무력화"
  writeLines(src, ap, useBytes = TRUE)
  ENM <- rfv_env(MX)
  sm0 <- rfv_asof_reselect(FX, ENM, LIN, DEP, OFF); sm1 <- rfv_asof_reselect(FX2, ENM, LIN, DEP, OFF)
  chk(!identical(sm0$picked_ids, sm1$picked_ids) || X %in% sm1$picked_ids,
      "M1 돌연변이는 I1 불변성을 깨뜨린다(검사가 red 를 낸다)", paste(sm1$picked_ids, collapse = "+"))
  chk(!identical(sm1$pool$ic_max_usable, s1$pool$ic_max_usable), "M2 돌연변이 표본은 as-of 뒤 IC 를 포함한다(A2 가 red)",
      paste(sm1$pool$ic_max_usable, s1$pool$ic_max_usable))
}

# ═══ E 제외 술어 ═══
cat("\n[E] 제외 술어\n")
EX <- rfv_load_cfg(CFGP)$exclusion
base <- list(vintage_flags = list(), measurement_regime = list(exec_price = EX$exec_price_required),
             entry = list(measurement_axis = "AX"), ledger_current_axis = "AX", adversary = list(ok = TRUE, status = "pass"),
             essence = list(port_t = 1.0))
chk(isTRUE(rfv_assess(base, EX)$eligible), "E1 깨끗한 합성 칸 = 자격")
b <- base; b$vintage_flags <- list(list(flag = as.character(EX$pit_flags[[1]])))
chk(!rfv_assess(b, EX)$eligible, "E2 PIT 표식 → 제외")
b <- base; b$vintage_flags <- list(list(flag = "fdb_202608_v1")); r <- rfv_assess(b, EX)
chk(isTRUE(r$eligible) && length(r$caveats) == 1L, "E3 비PIT 빈티지 표식 → caveat 만(자격 유지)")
b <- base; b$measurement_regime$exec_price <- "close_d"
chk(!rfv_assess(b, EX)$eligible, "E4 exec_price 불일치 → 제외")
b <- base; b$entry$measurement_axis <- "OLD"
chk(!rfv_assess(b, EX)$eligible, "E5 entry 축 ≠ current_axis → 제외")
b <- base; b$adversary <- list(ok = FALSE, status = "unverified")
chk(!rfv_assess(b, EX)$eligible, "E6 적대검증 미검증 → 제외")
b <- base; b$essence$port_t <- NA
chk(!rfv_assess(b, EX)$eligible, "E7 미측정 → 제외")
chk(!rfv_assess(base, EX, list(list(base_id = "Z", exposed = TRUE)))$eligible, "E8 Q④ 노출 → 제외")
chk(!rfv_assess(base, EX, list(list(base_id = "Z", exposed = NA)))$eligible, "E9 Q④ 재료 판독 불가 → 제외(fail-closed)")
chk(isTRUE(rfv_assess(base, EX, list(list(base_id = "Z", exposed = FALSE)))$eligible), "E10 Q④ 비노출 → 자격 유지")
r11 <- rfv_assess(base, EX, list(list(kind = "base_engine", file = "Z", exposed = TRUE)))
chk(!r11$eligible && any(startsWith(r11$reasons, "derived:q4_base_engine_exposure(")), "E11 기저 엔진 설계 노출 → 제외(노출 사유)", r11$reasons)
r12 <- rfv_assess(base, EX, list(list(kind = "base_engine", file = "Z", exposed = NA)))
chk(!r12$eligible && any(startsWith(r12$reasons, "derived:q4_base_engine_unknown(")), "E12 기저 엔진 재료 판독 불가 → 제외(fail-closed · 판독 불가 사유)", r12$reasons)
chk(isTRUE(rfv_assess(base, EX, list(list(kind = "base_engine", file = "Z", exposed = FALSE)))$eligible), "E13 기저 엔진 비노출 → 자격 유지")

# ═══ X Q④ 노출 검출기 ═══
cat("\n[X] Q④ 노출 검출기\n")
DX <- EX$design_exposure
XR <- file.path(TMP, "rfv_xr"); md <- file.path(XR, DX$materials_dir); dir.create(md, recursive = TRUE, showWarnings = FALSE)
hdr <- "## 앞선 논문들에서 이미 배운 것 (2블록) — 기저가 달라도 옮겨 붙는 것만"
wr <- function(id, lines) writeLines(enc2utf8(lines), file.path(md, paste0(id, DX$materials_suffix)), useBytes = TRUE)
wr("S1", c("## 기저", "- 기저 등급 B · 다중검정 t 2.852", hdr, "- 기전: C03_EPS_Chg_3m 은 PORT_t 3.202 로 올랐다", "## 다음"))
wr("S2", c(hdr, "- 기전: 2002.06975 논문 계열 · 25종 고정", "## 다음"))
wr("S3", c("## 기저", "- Calmar 0.427", "## 후보 팩터 등록부"))
chk(isTRUE(rfv_design_exposure(XR, "S1", DX)$exposed), "X1 절 안 통계 → 노출")
chk(identical(rfv_design_exposure(XR, "S2", DX)$exposed, FALSE), "X2 식별자(arXiv id)·정수 개수만 → 비노출")
chk(identical(rfv_design_exposure(XR, "S3", DX)$exposed, FALSE), "X3 절 없음(기저 절 수치만) → 비노출(자기 entry 는 대상 아님)")
chk(is.na(rfv_design_exposure(XR, "S9", DX)$exposed), "X4 파일 없음 → NA")
DXm <- DX; DXm$protect_regex <- list()
chk(isTRUE(rfv_design_exposure(XR, "S2", DXm)$exposed), "X5 돌연변이(식별자 보호 제거) → arXiv id 오판(보호식이 일을 한다)")

# ═══ B 기저 엔진 설계 노출(적대검증 수리 2026-09-25) ═══
cat("\n[B] 기저 엔진 설계 노출\n")
BX <- EX$base_engine_exposure
BR <- file.path(TMP, "rfv_bx"); unlink(BR, recursive = TRUE)
mkeng <- function(id, lines) {
  d <- file.path(BR, "04_Research/strategies", id); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines("# engine", file.path(d, "engine.R"))
  if (!is.null(lines)) writeLines(enc2utf8(lines), file.path(d, BX$materials_file), useBytes = TRUE)
  list(kind = "engine", path = file.path(d, "engine.R"))
}
b1 <- mkeng("E1", c("## 재료 논문", "1. x", "## 이 재료들의 이전 구현 (참고용)",
                    "- 2002.06975 : 04_Research/strategies/RP_AUTO_2002_06975/engine.R  (단독 다중검정 t 3.589)", "## 설계"))
b2 <- mkeng("E2", c("## 이 재료들의 이전 구현 (참고용)", "- 2002.06975 : 04_Research/strategies/RP_AUTO_2002_06975/engine.R", "## 설계"))
b3 <- mkeng("E3", c("## 논문", "- 2002.06975 · Calmar 0.5 목표", "## 산출"))
b4 <- mkeng("E4", NULL)
b5 <- mkeng("E5", c("## 실측 기록 (자료)", "이 재료 집합의 최고 단독 t 는 3.589 이고", "## 산출"))
chk(isTRUE(rfv_base_engine_exposure(BR, b1, BX, DX)$exposed), "B1 '이전 구현' 절의 교차 entry t → 노출")
chk(identical(rfv_base_engine_exposure(BR, b2, BX, DX)$exposed, FALSE), "B2 식별자·경로만 → 비노출")
chk(identical(rfv_base_engine_exposure(BR, b3, BX, DX)$exposed, FALSE), "B3 대상 절 밖 수치 → 비노출")
chk(is.na(rfv_base_engine_exposure(BR, b4, BX, DX)$exposed), "B4 설계 프롬프트 없음 → NA")
chk(isTRUE(rfv_base_engine_exposure(BR, b5, BX, DX)$exposed), "B5 둘째 시작 정규식('실측 기록' 절)도 본다")
DXm2 <- DX; DXm2$protect_regex <- list()
chk(isTRUE(rfv_base_engine_exposure(BR, b2, BX, DXm2)$exposed), "B6 돌연변이(식별자 보호 제거) → 오판 — 칸 팩터 판정과 같은 보호식을 쓴다")
chk(isTRUE(d1$floors$F1$base_engine_exposure$exposed) &&
      identical(d1$floors$F1$base_engine_exposure$engine_id, basename(dirname(.rfv_np(SP$base_signal$path)))),
    "B7 실데이터 양성 대조 — F1 기저 엔진(22632 결합 엔진) 설계 프롬프트 = 노출", d1$floors$F1$base_engine_exposure$file)
chk(any(grepl("q4_base_engine_exposure", unlist(d1$lineage_reference$assess$reasons))), "B8 계보 칸 판정에 기저 엔진 사유가 실린다")
chk(identical(d1$floors$F3_DNN$base_engine_exposure$exposed, FALSE) && !any(grepl("q4_base_engine", unlist(d1$floors$F3_DNN$assess$reasons))),
    "B9 실데이터 음성 대조 — 충실구현 엔진(RP_AUTO_2002_06975) 설계 프롬프트 = 비노출")

# ═══ G 사전등록 관문(적대검증 수리) ═══
cat("\n[G] 사전등록 관문\n")
PG <- rfv_load_cfg(CFGP)$prereg_gate
G0 <- d1$prereg_gate
chk(identical(G0$ready, FALSE) && any(grepl("^F1:q4_base_engine_exposure", unlist(G0$blockers))), "G1 실데이터 — 관문 닫힘(F1 기저 엔진 노출)",
    paste(unlist(G0$blockers), collapse = " ; "))
gids <- vapply(PG$required_decisions, function(d) as.character(d$id), "")
chk(length(gids) >= 1L && all(vapply(gids, function(i) any(grepl(paste0("decision_pending:", i, "("), unlist(G0$blockers), fixed = TRUE)), logical(1))),
    "G2 필수 결정(레지스터 미등록) → 전부 blocker")
GR <- file.path(TMP, "rfv_gr"); unlink(GR, recursive = TRUE); dir.create(file.path(GR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
RGP <- file.path(GR, .rfv_chr1(PG$register))
regs <- lapply(gids, function(i) list(id = i, status = "resolved", decision = "x"))
write_json(regs, RGP, auto_unbox = TRUE)
clean <- list(exposed = FALSE, file = "E2/prompt.txt")
g3 <- rfv_prereg_gate(GR, PG, clean, "pending_decision", BX)
chk(isTRUE(g3$ready) && !length(g3$blockers), "G3 양성 대조 — 결정 전부 resolved ∧ 기저 비노출 → ready(관문은 열릴 수 있다)")
regs2 <- regs; regs2[[1]]$status <- "open"; write_json(regs2, RGP, auto_unbox = TRUE)
chk(!isTRUE(rfv_prereg_gate(GR, PG, clean, "pending_decision", BX)$ready), "G4 결정 하나가 open → 닫힘")
write_json(regs, RGP, auto_unbox = TRUE)
chk(!isTRUE(rfv_prereg_gate(GR, PG, list(exposed = NA, file = "x"), "pending_decision", BX)$ready), "G5 기저 엔진 판독 불가 → 닫힘(fail-closed)")
CID <- as.character(BX$clearing$decision_id)
setdec <- function(txt) { r <- regs; for (k in seq_along(r)) if (identical(r[[k]]$id, CID)) r[[k]]$decision <- txt; write_json(r, RGP, auto_unbox = TRUE) }
setdec("Q④(a) — C1 possible · A 보류")
chk(!isTRUE(rfv_prereg_gate(GR, PG, list(exposed = TRUE, file = "x"), "pending_decision", BX)$ready), "G6 기저 엔진 노출 + 해제 결정 'Q④' → 닫힘(결정 전부 resolved 여도)")
setdec("Q① — 다중검정 + 서류 감사")
g8 <- rfv_prereg_gate(GR, PG, list(exposed = TRUE, file = "x"), "pending_decision", BX)
chk(isTRUE(g8$ready) && identical(g8$f1_base_engine_cleared_by$decision_id, CID), "G8 해제 결정 'Q① …' resolved → F1 blocker 해제 · 근거 기록")
chk(!isTRUE(rfv_prereg_gate(GR, PG, list(exposed = TRUE, file = "x"), "pending_decision", NULL)$ready), "G9 해제 규칙 없이 노출 → 닫힘")
r10 <- regs; for (k in seq_along(r10)) if (identical(r10[[k]]$id, CID)) { r10[[k]]$status <- "open"; r10[[k]]$decision <- "Q① — 다중검정" }
write_json(r10, RGP, auto_unbox = TRUE)
chk(!isTRUE(rfv_prereg_gate(GR, PG, list(exposed = TRUE, file = "x"), "pending_decision", BX)$ready), "G10 해제 문구가 있어도 결정이 open 이면 닫힘")
write_json(regs, RGP, auto_unbox = TRUE)
unlink(RGP)
g7 <- rfv_prereg_gate(GR, PG, clean, "pending_decision", BX)
chk(!isTRUE(g7$ready) && all(grepl("register_unreadable", grep("^decision_pending", g7$blockers, value = TRUE))) && length(g7$blockers) == length(gids),
    "G7 레지스터 판독 불가 → 전 결정 blocker(fail-closed)")

# ═══ V 적대검증 위임 ═══
cat("\n[V] 적대검증 상태 = 정본 술어\n")
L1 <- rfv_ledger(FX)
f2 <- .rfv_find(L1, d1$floors$F2$cite$base_id, d1$floors$F2$cite$cell_code)
sp <- .rfv_json(f2$attempt[["essence"]]$spec)
dir_ <- EN$rf_adversary_status(f2$attempt, carry_overlay = f2$entry$carry$overlay, spec = sp)
chk(identical(dir_$status, d1$floors$F2$cite$adversary$status), "V1 문서 상태 = 정본 술어 직접 호출", paste(dir_$status, d1$floors$F2$cite$adversary$status))
a2 <- f2$attempt; a2$adversary <- list(verdict = "pass")
chk(isTRUE(EN$rf_adversary_status(a2, f2$entry$carry$overlay, sp)$ok), "V2 verdict pass 주입 → ok(술어가 반응한다)")

# ═══ W 쓰기 ═══
cat("\n[W] 쓰기(사전등록 불변성)\n")
out <- file.path(TMP, "rfv_out", "reference_floors_v2.json"); unlink(dirname(out), recursive = TRUE)
chk(identical(rfv_write(d1, out), "written"), "W1 새 파일 written")
chk(identical(rfv_write(d2, out), "already"), "W2 같은 내용(생성 시각만 다름) already")
h0 <- unname(tools::md5sum(out)); m <- d1; m$floors$F1$reselect$picked_ids <- rev(m$floors$F1$reselect$picked_ids)
e <- tryCatch({ rfv_write(m, out); "no_error" }, error = function(e) "error")
chk(identical(e, "error") && identical(unname(tools::md5sum(out)), h0), "W3 내용이 다르면 거부 · 파일 불변")
alt <- .rfv_rt(d1); alt <- .rfv_norm(alt, FX); alt <- rapply(alt, function(v) gsub("<ROOT>", "D:/other_root/QM", v, fixed = TRUE), classes = "character", how = "replace")
alt$generator$root <- "D:/other_root/QM"; alt$generator$code_root <- "D:/other_root/QM"
chk(identical(rfv_write(alt, out), "already"), "W4 생성 루트만 다른 같은 문서 = already(경로 정규화)")
alt2 <- alt; alt2$floors$F3_DNN$cite$essence$port_t <- as.numeric(alt2$floors$F3_DNN$cite$essence$port_t) + 0.001
e2 <- tryCatch({ rfv_write(alt2, out); "no_error" }, error = function(e) "error")
chk(identical(e2, "error"), "W5 경로 정규화가 수치 차이를 가리지 않는다")

# ═══ P 핀 대조(rfv_verify) ═══
cat("
[P] 핀 대조
")
v0 <- rfv_verify(out, FX, CFGP, FX, EN)
chk(v0$n_drift == 0L && !length(v0$citations), "P1 같은 입력 재생성 = 드리프트 0 · 인용 일치", head(v0$drift, 3))
FX3 <- file.path(TMP, "rfv_fx3"); unlink(FX3, recursive = TRUE)
invisible(vapply(need, cp, logical(1), dst_root = FX3))
lp <- file.path(FX3, "06_Registry/reinforce_ledger_l1.json"); LJ <- fromJSON(lp, simplifyVector = FALSE)
bid <- d1$floors$F3_DNN$cite$base_id; nn <- as.character(d1$floors$F3_DNN$cite$n)
for (i in seq_along(LJ$entries)) if (identical(LJ$entries[[i]]$base_id, bid))
  for (j in seq_along(LJ$entries[[i]]$attempts)) if (identical(as.character(LJ$entries[[i]]$attempts[[j]]$n), nn))
    LJ$entries[[i]]$attempts[[j]]$essence$calmar <- LJ$entries[[i]]$attempts[[j]]$essence$calmar + 0.01
writeLines(toJSON(LJ, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = FALSE), lp, useBytes = TRUE)
v1 <- rfv_verify(out, FX3, file.path(FX3, "06_Registry/prereg/reference_floors_v2.config.json"), FX3, EN)
chk(length(v1$floors_drift) > 0L && length(v1$pins_drift) > 0L && "F3_DNN:essence" %in% v1$citations,
    "P2 원장 변경 → 바닥 드리프트·핀 드리프트·인용 불일치 검출", paste(head(v1$floors_drift, 2), collapse = " ; "))

# ═══ F 설정 fail-closed ═══
cat("\n[F] 설정 fail-closed\n")
cfg <- fromJSON(CFGP, simplifyVector = FALSE)
bad1 <- cfg; bad1$exclusion$design_exposure <- NULL; p1 <- file.path(TMP, "rfv_bad1.json"); write_json(bad1, p1, auto_unbox = TRUE)
chk(inherits(tryCatch(rfv_load_cfg(p1), error = function(e) e), "error"), "F1 design_exposure 부재 → stop")
bad2 <- cfg; bad2$floors$F1$seed_rule$seed_offset <- -1; p2 <- file.path(TMP, "rfv_bad2.json"); write_json(bad2, p2, auto_unbox = TRUE)
chk(inherits(tryCatch(rfv_load_cfg(p2), error = function(e) e), "error"), "F2 seed_offset 음수 → stop")
bad3 <- cfg; bad3$exclusion$base_engine_exposure <- NULL; p3 <- file.path(TMP, "rfv_bad3.json"); write_json(bad3, p3, auto_unbox = TRUE)
chk(inherits(tryCatch(rfv_load_cfg(p3), error = function(e) e), "error"), "F3 base_engine_exposure 부재 → stop")
bad4 <- cfg; bad4$prereg_gate <- NULL; p4 <- file.path(TMP, "rfv_bad4.json"); write_json(bad4, p4, auto_unbox = TRUE)
chk(inherits(tryCatch(rfv_load_cfg(p4), error = function(e) e), "error"), "F4 prereg_gate 부재 → stop")
bad5 <- cfg; bad5$exclusion$base_engine_exposure$clearing$decision_id <- "NOT-REQUIRED-ID"; p5 <- file.path(TMP, "rfv_bad5.json"); write_json(bad5, p5, auto_unbox = TRUE)
chk(inherits(tryCatch(rfv_load_cfg(p5), error = function(e) e), "error"), "F5 해제 결정 id 가 필수 결정 밖 → stop")

# ═══ S F1 스펙 구조 ═══
cat("\n[S] F1 스펙 구조\n")
spf <- vapply(SP$factors, function(f) f$id, "")
chk(identical(spf, F1ids), "S1 스펙 팩터 = 재선정 집합(순서 포함)")
LS <- .rfv_json(d1$lineage_reference$cite$spec_path); G <- .rfv_json(file.path(FX, "06_Registry/reinforce_program.json"))
chk(identical(.rfv_rt(SP$base_signal), .rfv_rt(LS$base_signal)), "S2 기저 엔진 = 계보 칸 스펙")
chk(identical(.rfv_rt(SP$fixed_axes), .rfv_rt(G$fixed_axes)) && identical(SP$base_weight, G$fixed_axes$base_weight), "S3 fixed_axes·base_weight = 격자")
chk(!length(SP$overlay) && !length(SP$overlay_cell), "S4 오버레이 없음")
chk(identical(length(F1ids), length(LIN)) && identical(d1$floors$F1$selection_path$depth, length(LIN)), "S5 깊이 = 계보 칸 DB 팩터 수")
ss <- rfv_asof_reselect(FX, EN, F1ids, DEP, OFF)
chk(isTRUE(ss$compare$same_set) && startsWith(ss$compare$verdict, "same_set"), "S6 '같으면' 분기 양성 대조(계보 집합 = as-of 집합 → same_set · 표식 해제 아님 문구)")
chk(identical(d1$floors$F1$reselect$compare$same_set, setequal(F1ids, LIN)), "S7 비교 판정 = setequal 재도출")
CF <- rfv_load_cfg(CFGP)
Xd <- EN$rf_pick_factor_sets(n = 1L, depths = length(LIN), seed_offset = as.integer(CF$floors$F1$seed_rule$seed_offset), root = FX, asof = CF$asof)
chk(identical(vapply(Xd$cells[[1]]$factors, function(f) f$id, ""), F1ids) && identical(Xd$cells[[1]]$label, SP$label),
    "S8 F1 = 설정 규칙으로 정본 선정기를 직접 부른 결과(시드·깊이·as-of 재현)")

# ═══ R 읽기 전용 ═══
cat("\n[R] 읽기 전용\n")
chk(identical(md5_prod(), PROD0), "R1 루트 지문 불변")
chk(identical(sort(list.files(file.path(ROOT, "06_Registry/prereg"))), PRE0), "R2 루트 prereg 폴더 불변")
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
