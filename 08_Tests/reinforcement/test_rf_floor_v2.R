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
#   (통합 2026-09-25 밤) K 사전등록 소비 계약 필드(바닥 층 id·status·determinism_ok·selection_basis(범주)·measurement_regime · 소비자 .rfp_floor_check
#      대조 — 루트에 rf_prereg.R 가 있을 때) · H 관문 사용 제한(Q④ → mechanism_only · Q① → A · 모호 멈춤) · Q 결정론 기록(대조·거부·
#      판독·stale·종합·상태 규칙·rfv_build 통합) · U 개정(supersede — 색인 등록본·판독 불가·status·이력 보존) · MK 돌연변이 4종 ·
#      G1·G2 를 레지스터 재도출로 바꿈(구판은 운영 레지스터의 '미등록' 상태를 빌려 결정 등록 뒤 red)
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
# ★통합(2026-09-25 밤) — 구판 G1·G2 는 운영 레지스터 상태(결정 미등록)를 빌려 단정했다: 결정이 21:38 에 resolved 로 들어오자 G2 가 깨졌다
#   (검사가 운영 상태를 빌리면 그 상태를 고칠 때 깨진다). 실데이터 판정은 레지스터에서 **재도출**하고, '미등록 → blocker' 는 합성 레지스터로 잰다.
gids <- vapply(PG$required_decisions, function(d) as.character(d$id), "")
CID <- as.character(BX$clearing$decision_id)
chk(identical(G0$ready, FALSE) == (isTRUE(d1$floors$F1$base_engine_exposure$exposed) && is.null(G0$f1_base_engine_cleared_by)) &&
      any(grepl("^F1:q4_base_engine_exposure", unlist(G0$blockers))) == is.null(G0$f1_base_engine_cleared_by),
    "G1 실데이터 — F1 기저 엔진 blocker = 노출 ∧ 해제 결정 부재(재도출)", paste(unlist(G0$blockers), collapse = " ; "))
RG0 <- tryCatch(fromJSON(file.path(FX, .rfv_chr1(PG$register)), simplifyVector = FALSE), error = function(e) NULL)
RG0i <- if (is.list(RG0) && !is.null(RG0$items)) RG0$items else RG0
st_of <- function(i) { h <- Filter(function(z) is.list(z) && identical(.rfv_chr1(z$id), i), RG0i); if (!length(h)) "absent" else .rfv_chr1(h[[length(h)]]$status) }
chk(all(vapply(gids, function(i) any(grepl(paste0("decision_pending:", i, "("), unlist(G0$blockers), fixed = TRUE)) == !identical(st_of(i), "resolved"), logical(1))),
    "G2 실데이터 — 필수 결정 blocker = 레지스터에서 resolved 가 아닌 것(재도출)", paste(vapply(gids, st_of, ""), collapse = ","))
GR <- file.path(TMP, "rfv_gr"); unlink(GR, recursive = TRUE); dir.create(file.path(GR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
RGP <- file.path(GR, .rfv_chr1(PG$register))
write_json(list(items = list(list(id = "OTHER", status = "resolved", decision = "x"))), RGP, auto_unbox = TRUE)
g2b <- rfv_prereg_gate(GR, PG, list(exposed = FALSE, file = "x"), "pending_decision", BX)
chk(!isTRUE(g2b$ready) && all(vapply(gids, function(i) any(grepl(paste0("decision_pending:", i, "(absent)"), g2b$blockers, fixed = TRUE)), logical(1))),
    "G2b 합성 레지스터(필수 결정 미등록) → 전부 blocker(absent)")
regs <- lapply(gids, function(i) list(id = i, status = "resolved", decision = "x"))
write_json(regs, RGP, auto_unbox = TRUE)
clean <- list(exposed = FALSE, file = "E2/prompt.txt")
g3 <- rfv_prereg_gate(GR, PG, clean, "pending_decision", BX)
chk(isTRUE(g3$ready) && !length(g3$blockers), "G3 양성 대조 — 결정 전부 resolved ∧ 기저 비노출 → ready(관문은 열릴 수 있다)")
regs2 <- regs; regs2[[1]]$status <- "open"; write_json(regs2, RGP, auto_unbox = TRUE)
chk(!isTRUE(rfv_prereg_gate(GR, PG, clean, "pending_decision", BX)$ready), "G4 결정 하나가 open → 닫힘")
write_json(regs, RGP, auto_unbox = TRUE)
chk(!isTRUE(rfv_prereg_gate(GR, PG, list(exposed = NA, file = "x"), "pending_decision", BX)$ready), "G5 기저 엔진 판독 불가 → 닫힘(fail-closed)")
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


chk2 <- function(name, cond, detail = "") chk(cond, name, detail)   # (통합 블록) 이름 먼저 표기
# ═══ K 사전등록 소비 계약 필드(통합 2026-09-25 밤) ═══
cat("\n[K] 사전등록 소비 계약 필드\n")
CF0 <- rfv_load_cfg(CFGP); CC <- CF0$consumer_contract
d1j <- fromJSON(toJSON(d1, auto_unbox = TRUE, null = "null", na = "null", digits = NA), simplifyVector = FALSE)   # 저장 형태(JSON 왕복)
req <- as.character(unlist(CC$required_fields))
chk2("K1 모든 바닥 층에 소비 필드(id·status·determinism_ok·selection_basis·measurement_regime) — JSON 왕복 뒤에도 이름 존재",
    all(vapply(names(d1j$floors), function(k) all(req %in% names(d1j$floors[[k]])), logical(1))),
    paste(names(d1j$floors), collapse = ","))
F1j <- d1j$floors$F1
chk2("K2 F1 selection_basis = 범주 as_of · 세부 = 스펙 asof_ic(P0-14 관문 필드 불변)",
    identical(F1j$selection_basis, "as_of") && identical(F1j$selection_basis_detail, "asof_ic") && identical(F1j$spec$selection_basis, "asof_ic"))
chk2("K3 F1 측정 전 = determinism_ok null · status defined_unmeasured · 규약 선언값(exec_price = 요구 · basis declared)",
    is.null(F1j$determinism_ok) && identical(F1j$status, "defined_unmeasured") && identical(F1j$measurement_regime$exec_price, CF0$exclusion$exec_price_required) &&
      startsWith(F1j$measurement_regime$basis, "declared"))
chk2("K4 F2(전표본 승계 표식) selection_basis = full_sample(표식이 사상보다 우선)", identical(d1j$floors$F2$selection_basis, "full_sample"))
chk2("K5 범주 함수 — 표식 우선 · 사상 · 미지", identical(rfv_sb_category("asof_ic", "selection_basis_full_sample_ic_inherited", CC), "full_sample") &&
      identical(rfv_sb_category("asof_ic", character(0), CC), "as_of") && identical(rfv_sb_category("weird", character(0), CC), "unknown"))
cfk <- fromJSON(CFGP, simplifyVector = FALSE)
b6 <- cfk; b6$consumer_contract$selection_basis_category$full_sample_ic <- "as_of"; p6 <- file.path(TMP, "rfv_bad6.json"); write_json(b6, p6, auto_unbox = TRUE)
chk2("K6 설정 — full_sample 세부 값을 as_of 로 사상 → stop(C1 칸이 소비 검사를 통과하지 못하게)", inherits(tryCatch(rfv_load_cfg(p6), error = function(e) e), "error"))
b7 <- cfk; b7$consumer_contract$selection_basis_ok <- list("as_of", "full_sample"); p7 <- file.path(TMP, "rfv_bad7.json"); write_json(b7, p7, auto_unbox = TRUE)
chk2("K7 설정 — selection_basis_ok 에 full_sample → stop", inherits(tryCatch(rfv_load_cfg(p7), error = function(e) e), "error"))
b8 <- cfk; b8$determinism <- NULL; p8 <- file.path(TMP, "rfv_bad8.json"); write_json(b8, p8, auto_unbox = TRUE)
chk2("K8 설정 — determinism 부재 → stop", inherits(tryCatch(rfv_load_cfg(p8), error = function(e) e), "error"))
# 소비자 대조 — 사전등록 계약(rf_prereg.R)이 루트에 있으면 그 바닥 검사를 이 문서로 돌린다(없으면 생략 — 미배포)
PRF <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"); PCF <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
if (file.exists(PRF) && file.exists(PCF)) {
  PE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(PRF, envir = PE, keep.source = FALSE)))
  KR <- file.path(TMP, "rfv_kroot"); unlink(KR, recursive = TRUE)
  dir.create(file.path(KR, "02_Infrastructure"), recursive = TRUE); dir.create(file.path(KR, "06_Registry/prereg"), recursive = TRUE)
  writeLines("# fixture", file.path(KR, "02_Infrastructure/config.R")); file.copy(PCF, file.path(KR, "06_Registry/prereg/prereg_config.json"))
  pcfg <- PE$rf_prereg_config(KR)
  writeLines(toJSON(d1, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = TRUE), file.path(KR, pcfg$registration$floor_ref_path))
  pr_syn <- list(floors = list(list(id = "F1")), measurement_regime = list(exec_price = CF0$exclusion$exec_price_required))
  ek <- PE$.rfp_floor_check(pr_syn, KR, pcfg)
  chk2("K9 소비자(.rfp_floor_check) — 필드 부재·selection_basis·규약 사유 0 · 남는 사유 = status·결정론(측정 전)",
      !any(grepl("필드 부재|selection_basis|규약", ek)) && any(grepl("status=defined_unmeasured", ek)) && any(grepl("결정론 미확인", ek)), paste(ek, collapse = " | "))
  dm <- d1; dm$floors$F1$status <- "confirmed_mechanism_only"; dm$floors$F1$determinism_ok <- TRUE
  writeLines(toJSON(dm, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = TRUE), file.path(KR, pcfg$registration$floor_ref_path))
  ek2 <- PE$.rfp_floor_check(pr_syn, KR, pcfg)
  chk2("K10 소비자 — confirmed_mechanism_only 는 현 소비 계약(floor_status_ok = confirmed)에서 거부된다(fail-closed · 명시 수용 전)",
      any(grepl("confirmed_mechanism_only", ek2)), paste(ek2, collapse = " | "))
} else { SKIP <- SKIP + 2L; cat("  SKIP K9·K10 사전등록 계약(rf_prereg.R · prereg_config.json) 루트 부재 — 미배포\n") }

# ═══ H 관문 사용 제한(결정 Q④ → 기전 한정) ═══
cat("\n[H] 관문 사용 제한\n")
HR <- file.path(TMP, "rfv_hr"); unlink(HR, recursive = TRUE); dir.create(file.path(HR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
HRG <- file.path(HR, .rfv_chr1(PG$register))
hreg <- function(q4, open_id = NULL) {
  r <- lapply(gids, function(i) list(id = i, status = if (identical(i, open_id)) "open" else "resolved", decision = if (identical(i, CID)) q4 else "x"))
  write_json(list(items = r), HRG, auto_unbox = TRUE)
}
EXPO <- list(exposed = TRUE, file = "E1/prompt.txt")
hreg("Q④(C1 possible)로 분류 — 기전 반증 시도(mechanism_only)")
h1 <- rfv_prereg_gate(HR, PG, EXPO, "possible", BX)
chk2("H1 해제 결정 'Q④ …' resolved → A 경로 닫힘(ready FALSE) · 기전 한정 열림 · use_restriction{mechanism_only · a_eligible FALSE}",
    identical(h1$ready, FALSE) && isTRUE(h1$ready_mechanism_only) && identical(h1$use_restriction$kind, "mechanism_only") && identical(h1$use_restriction$a_eligible, FALSE) &&
      !length(h1$blockers_mechanism_only))
hreg("Q④ — 기전 한정", open_id = setdiff(gids, CID)[1])
h2 <- rfv_prereg_gate(HR, PG, EXPO, "possible", BX)
chk2("H2 Q④ 이지만 다른 필수 결정 open → 기전 한정도 닫힘", identical(h2$ready_mechanism_only, FALSE) && length(h2$blockers_mechanism_only) == 1L)
hreg("Q① — 다중검정 + 서류 감사")
h3 <- rfv_prereg_gate(HR, PG, EXPO, "possible", BX)
chk2("H3 Q① → A 경로 열림 · 제한 없음", isTRUE(h3$ready) && is.null(h3$use_restriction) && isTRUE(h3$ready_mechanism_only))
BXa <- BX; BXa$clearing$restricts_if_decision_matches <- list("^\\s*Q")
hreg("Q① — 다중검정")
chk2("H4 한 문구가 해제·제한 규칙에 동시에 맞으면 멈춘다(분류 모호)", inherits(tryCatch(rfv_prereg_gate(HR, PG, EXPO, "possible", BXa), error = function(e) e), "error"))
b9 <- cfk; b9$exclusion$base_engine_exposure$clearing$restriction <- ""; p9 <- file.path(TMP, "rfv_bad9.json"); write_json(b9, p9, auto_unbox = TRUE)
chk2("H5 설정 — 제한 규칙은 있는데 제한 이름 없음 → stop", inherits(tryCatch(rfv_load_cfg(p9), error = function(e) e), "error"))
chk2("H6 실데이터 — 문서 관문 = 레지스터 재도출(제한 여부는 결정 문구가 정한다)", {
  RR <- tryCatch(fromJSON(file.path(FX, .rfv_chr1(PG$register)), simplifyVector = FALSE), error = function(e) NULL)
  items <- if (is.list(RR) && !is.null(RR$items)) RR$items else RR
  hit <- Filter(function(z) is.list(z) && identical(.rfv_chr1(z$id), CID) && identical(.rfv_chr1(z$status), "resolved"), items)
  dec <- if (length(hit)) .rfv_chr1(hit[[length(hit)]]$decision) else ""
  want_r <- nzchar(dec) && grepl(as.character(unlist(BX$clearing$restricts_if_decision_matches))[1], dec, perl = TRUE)
  identical(!is.null(G0$use_restriction), want_r) })

# ═══ Q 결정론 기록(등록 전 측정 단계 → determinism_ok) ═══
cat("\n[Q] 결정론 기록\n")
QR <- file.path(TMP, "rfv_qr"); unlink(QR, recursive = TRUE)
invisible(vapply(need, cp, logical(1), dst_root = QR))
QDOC <- file.path(QR, "06_Registry/prereg/reference_floors_v2.json"); QCFG <- file.path(QR, "06_Registry/prereg/reference_floors_v2.config.json")
dq <- rfv_build(QR, QCFG, QR, EN); invisible(rfv_write(dq, QDOC))
DTC <- rfv_load_cfg(QCFG)$determinism
spec_f <- file.path(TMP, "rfv_f1_spec.json"); writeLines(toJSON(dq$floors$F1$spec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), spec_f)
mk_run <- function(dir, run_id, idea = dq$floors$F1$spec$idea, bump = 0, vint = "v1", exec = "close_t1", calmar = 0.5, dsr = 0.7, fp = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dd <- seq(as.Date("2010-01-04"), by = "day", length.out = 40)
  fwrite(data.table(run_id = run_id, strategy_id = paste0("RP_", run_id), date = dd, ret_net = sin(seq_along(dd)) / 100 + bump, ret_gross = sin(seq_along(dd)) / 100),
         file.path(dir, "03_period_returns.csv"))
  fwrite(data.table(run_id = run_id, strategy_id = paste0("RP_", run_id), date = rep(dd[c(1, 21)], each = 3), ticker = rep(c("A1", "A2", "A3"), 2), actual_weight = 1 / 3),
         file.path(dir, "04_holdings.csv"))
  fwrite(data.table(benchmark_id = "KOSPI200", date = dd, benchmark_ret = cos(seq_along(dd)) / 100), file.path(dir, "05_benchmark_returns.csv"))
  writeLines(toJSON(list(run_id = run_id, strategy_idea = paste("[prereg 결정론]", idea)), auto_unbox = TRUE), file.path(dir, "01_strategy_spec.json"))
  writeLines(toJSON(list(essence_grade = "B", essence = list(calmar = calmar, dsr = dsr, port_t = 3.1),
                         measurement_regime = c(list(key = paste0(exec, "_k1"), exec_price = exec, harness_md5 = "h1", cost_model_version = "cm1",
                                                     data_vintage = list(raw = list(size = 1, mtime = vint))),
                                                if (!is.null(fp)) list(data_cutoff = "2026-09-18", data_fingerprint = fp))), auto_unbox = TRUE, digits = NA),
             file.path(dir, "authoritative_remeasure.json"))
  dir
}
rA <- mk_run(file.path(TMP, "runA"), "R1"); rB <- mk_run(file.path(TMP, "runB"), "R2", dsr = 0.69)
q1 <- rfv_determinism_check(c(rA, rB), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)
chk2("Q1 같은 스펙 2회 · 실행 식별 열·DSR(시행 수 의존)만 다름 → determinism_ok TRUE", isTRUE(q1$determinism_ok) && identical(q1$verdict, "deterministic"), paste(q1$reasons, collapse = ","))
rC <- mk_run(file.path(TMP, "runC"), "R3", bump = 1e-9)
chk2("Q2 수익 1e-9 차이 → FALSE(nondeterministic)", identical(rfv_determinism_check(c(rA, rC), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)$determinism_ok, FALSE))
rD <- mk_run(file.path(TMP, "runD"), "R4", calmar = 0.51)
chk2("Q3 essence(Calmar) 차이 → FALSE", identical(rfv_determinism_check(c(rA, rD), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)$determinism_ok, FALSE))
rE <- mk_run(file.path(TMP, "runE"), "R5", vint = "v2")
qe <- rfv_determinism_check(c(rA, rE), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)
chk2("Q4 데이터 빈티지가 다르면 판정 불가(NA · inconclusive)", is.na(qe$determinism_ok) && grepl("inconclusive", qe$verdict))
rI <- mk_run(file.path(TMP, "runI"), "R8", vint = "v1", fp = "FP1"); rJ <- mk_run(file.path(TMP, "runJ"), "R9", vint = "v2", fp = "FP1")
rK <- mk_run(file.path(TMP, "runK"), "R10", vint = "v1", fp = "FP2")
chk2("Q4b 절단 지문(data_cutoff+data_fingerprint)이 같으면 파일 mtime 이 달라도 판정(TRUE)", isTRUE(rfv_determinism_check(c(rI, rJ), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)$determinism_ok))
chk2("Q4c 절단 지문이 다르면 판정 불가(NA)", is.na(rfv_determinism_check(c(rI, rK), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)$determinism_ok))
qs <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")
chk2("Q5 같은 산출물 두 번 → stop", qs(rfv_determinism_check(c(rA, rA), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)))
sp2 <- dq$floors$F1$spec; sp2$factors <- rev(sp2$factors); spec_f2 <- file.path(TMP, "rfv_f1_spec_other.json")
writeLines(toJSON(sp2, auto_unbox = TRUE, null = "null", na = "null", digits = NA), spec_f2)
chk2("Q6 스펙 파일 ≠ 바닥 문서 F1 스펙(팩터 순서) → stop", qs(rfv_determinism_check(c(rA, rB), spec_f2, dq$floors$F1$spec, DTC, "close_t1", roots = QR)))
sp3 <- dq$floors$F1$spec; sp3$gate_note <- "러너가 다듬은 서술"; sp3$root_papers <- NULL; spec_f3 <- file.path(TMP, "rfv_f1_spec_trim.json")
writeLines(toJSON(sp3, auto_unbox = TRUE, null = "null", na = "null", digits = NA), spec_f3)
chk2("Q6b 서술 필드만 다른 스펙 파일(러너가 다듬음) → 같은 칸으로 받는다(측정 정의 필드 지문)", isTRUE(rfv_determinism_check(c(rA, rB), spec_f3, dq$floors$F1$spec, DTC, "close_t1", roots = QR)$determinism_ok))
sp4 <- dq$floors$F1$spec; sp4$base_signal_md5 <- "0000"; spec_f4 <- file.path(TMP, "rfv_f1_spec_eng.json")
writeLines(toJSON(sp4, auto_unbox = TRUE, null = "null", na = "null", digits = NA), spec_f4)
chk2("Q6c 기저 엔진 md5 가 다른 스펙 → stop(측정 정의 필드)", qs(rfv_determinism_check(c(rA, rB), spec_f4, dq$floors$F1$spec, DTC, "close_t1", roots = QR)))
rF <- mk_run(file.path(TMP, "runF"), "R6", idea = "다른 칸")
chk2("Q7 산출물이 F1 idea 에 묶이지 않음 → stop", qs(rfv_determinism_check(c(rA, rF), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)))
rG <- mk_run(file.path(TMP, "runG"), "R7", exec = "close_d_legacy")
chk2("Q8 규약(exec_price) ≠ 요구 → stop", qs(rfv_determinism_check(c(rA, rG), spec_f, dq$floors$F1$spec, DTC, "close_t1", roots = QR)))
# 기록 → 판독 → 필드
rec1 <- rfv_determinism_record("F1", c(rA, rB), spec_f, QR, QCFG, QDOC)
chk2("Q9 기록 쓰기 = record_dir 아래 · 파일명에 스펙 지문", file.exists(rec1$path) && grepl(substr(rec1$record$spec_md5, 1, 12), basename(rec1$path), fixed = TRUE) &&
      inside(rec1$path, file.path(QR, DTC$record_dir)))
ld <- rfv_determinism_load(QR, DTC, "F1", dq$floors$F1$spec, QR)
chk2("Q10 판독 — TRUE · 실현 규약(exec_price close_t1)", isTRUE(ld$determinism_ok) && identical(ld$regime$exec_price, "close_t1"))
fq1 <- rfv_floor_fields("F1", "asof_ic", ld, rfv_load_cfg(QCFG), "AX", h1)
fq3 <- rfv_floor_fields("F1", "asof_ic", ld, rfv_load_cfg(QCFG), "AX", h3)
fq2 <- rfv_floor_fields("F1", "asof_ic", ld, rfv_load_cfg(QCFG), "AX", h2)
chk2("Q11 상태 — 결정론 ∧ as_of ∧ 실현 규약 · 관문(Q④ 제한) → confirmed_mechanism_only · a_eligible FALSE · permitted_use mechanism_only",
    identical(fq1$status, "confirmed_mechanism_only") && identical(fq1$a_eligible, FALSE) && identical(fq1$permitted_use, "mechanism_only") && startsWith(fq1$measurement_regime$basis, "realized"))
chk2("Q12 상태 — 관문 ready(Q①) → confirmed · a_eligible TRUE", identical(fq3$status, "confirmed") && isTRUE(fq3$a_eligible))
chk2("Q13 상태 — 필수 결정 open → gate_blocked", identical(fq2$status, "gate_blocked"))
fq4 <- rfv_floor_fields("F1", "full_sample_ic", ld, rfv_load_cfg(QCFG), "AX", h3)
chk2("Q14 상태 — 선정 기저 범주가 as_of 밖 → selection_basis_rejected", identical(fq4$status, "selection_basis_rejected"))
dqb <- rfv_build(QR, QCFG, QR, EN)
chk2("Q15 rfv_build 통합 — 기록이 문서 F1 층에 실린다(determinism_ok TRUE · 기록 1건 · 상태 = 규칙)", isTRUE(dqb$floors$F1$determinism_ok) && length(dqb$floors$F1$determinism$records) == 1L &&
      identical(dqb$floors$F1$status, .rfv_floor_status(TRUE, "as_of", dqb$floors$F1$measurement_regime, "close_t1", "as_of", dqb$prereg_gate)))
Sys.sleep(1.1); rec2 <- rfv_determinism_record("F1", c(rA, rC), spec_f, QR, QCFG, QDOC)
chk2("Q16 종합 — TRUE 기록 + FALSE 기록 → FALSE(비결정 우선)", identical(rfv_determinism_load(QR, DTC, "F1", dq$floors$F1$spec, QR)$determinism_ok, FALSE))
unlink(rec2$path)
fwrite(data.table(run_id = "R2", strategy_id = "RP_R2", date = as.Date("2010-01-04"), ret_net = 9, ret_gross = 9), file.path(rB, "03_period_returns.csv"))
lds <- rfv_determinism_load(QR, DTC, "F1", dq$floors$F1$spec, QR)
chk2("Q17 기록 뒤 산출물이 바뀌면 그 기록은 stale(무시) → NA", is.na(lds$determinism_ok) && length(lds$stale) == 1L && grepl("artifact_changed", lds$stale))
chk2("Q18 다른 스펙 지문의 기록은 읽지 않는다", is.na(rfv_determinism_load(QR, DTC, "F1", sp2, QR)$determinism_ok))
b10 <- cfk; b10$determinism$spec_fields <- list(); p10 <- file.path(TMP, "rfv_bad10.json"); write_json(b10, p10, auto_unbox = TRUE)
chk2("Q18b 설정 — determinism.spec_fields 비면 stop(지문 필드를 코드가 지어내지 않는다)", qs(rfv_load_cfg(p10)))
chk2("Q19 결정론 기록 대상 밖 바닥(F1p) → stop", qs(rfv_determinism_record("F1p", c(rA, rB), spec_f, QR, QCFG, QDOC)))

# ═══ U 개정(supersede) ═══
cat("\n[U] 개정(supersede)\n")
UR <- file.path(TMP, "rfv_ur"); unlink(UR, recursive = TRUE); dir.create(file.path(UR, "06_Registry/prereg"), recursive = TRUE)
UO <- file.path(UR, "06_Registry/prereg/reference_floors_v2.json"); UCF <- rfv_load_cfg(CFGP)
invisible(rfv_write(d1, UO)); h0u <- unname(tools::md5sum(UO))
m_u <- d1; m_u$floors$F1$status <- "changed_for_test"
chk2("U1 supersede 없이 내용이 다르면 거부(파일 불변)", qs(rfv_write(m_u, UO)) && identical(unname(tools::md5sum(UO)), h0u))
IX <- file.path(UR, UCF$revision$prereg_index)
writeLines(toJSON(list(kind = "registered", prereg_id = "PR-X"), auto_unbox = TRUE), IX)
chk2("U2 사전등록 색인에 등록본 → supersede 거부(파일 불변)", qs(rfv_write(m_u, UO, supersede = TRUE, root = UR, cfg = UCF)) && identical(unname(tools::md5sum(UO)), h0u))
writeLines(c(as.character(toJSON(list(kind = "draft", prereg_id = "PR-X"), auto_unbox = TRUE)), "{not json"), IX)
chk2("U3 색인 판독 불가 줄 → supersede 거부(fail-closed)", qs(rfv_write(m_u, UO, supersede = TRUE, root = UR, cfg = UCF)) && identical(unname(tools::md5sum(UO)), h0u))
writeLines(as.character(toJSON(list(kind = "draft", prereg_id = "PR-X"), auto_unbox = TRUE)), IX)
chk2("U4 root·cfg 없이 supersede → 거부", qs(rfv_write(m_u, UO, supersede = TRUE)))
ru <- rfv_write(m_u, UO, supersede = TRUE, root = UR, cfg = UCF)
nu <- fromJSON(UO, simplifyVector = FALSE); arch <- file.path(UR, nu$supersedes$path)
chk2("U5 초안 · 등록본 0 → superseded · 옛 판 이력 보존(md5 = 옛 파일) · supersedes 기록", identical(ru, "superseded") && file.exists(arch) &&
      identical(unname(tools::md5sum(arch)), h0u) && identical(nu$supersedes$md5, h0u) && identical(nu$floors$F1$status, "changed_for_test"))
chk2("U6 개정 뒤 같은 내용 재쓰기 = already(supersedes 는 비교 밖)", identical(rfv_write(m_u, UO), "already"))
m_u2 <- m_u; m_u2$status <- "registered_floor"; invisible(rfv_write(m_u2, UO, supersede = TRUE, root = UR, cfg = UCF))
m_u3 <- m_u2; m_u3$floors$F1$status <- "again"
chk2("U7 기존 판 status 가 허용 밖(초안 아님) → supersede 거부", qs(rfv_write(m_u3, UO, supersede = TRUE, root = UR, cfg = UCF)))

# ═══ MK 돌연변이(통합 필드) ═══
cat("\n[MK] 돌연변이 — 통합 필드\n")
fsrc <- readLines(file.path(FX, "02_Infrastructure/reinforcement/rf_floor_v2.R"), encoding = "UTF-8", warn = FALSE)
fmut <- function(from, to) {
  hit <- which(grepl(from, fsrc, fixed = TRUE)); if (length(hit) != 1L) return(NULL)
  s2 <- fsrc; s2[hit] <- sub(from, to, s2[hit], fixed = TRUE)
  p <- file.path(TMP, sprintf("rfv_mut_%d.R", sample.int(1e6, 1))); writeLines(s2, p, useBytes = TRUE)
  e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(p, envir = e, keep.source = FALSE))); e
}
mk1 <- fmut("if (length(fl) && any(grepl(.rfv_chr1(cc$full_sample_flag_regex), fl, perl = TRUE))) return(\"full_sample\")", "if (FALSE) return(\"full_sample\")")
chk2("MK1 전표본 표식 우선 제거 돌연변이 → K5 red(표식 칸이 as_of 로 샌다)", !is.null(mk1) && identical(mk1$rfv_sb_category("asof_ic", "selection_basis_full_sample_ic_inherited", CC), "as_of"))
mk2 <- fmut("if (isTRUE(gate$ready)) return(\"confirmed\")", "return(\"confirmed\")")
chk2("MK2 관문 무시 돌연변이 → Q11 red(Q④ 제한 바닥이 confirmed 로)", !is.null(mk2) && identical(mk2$rfv_floor_fields("F1", "asof_ic", ld, rfv_load_cfg(QCFG), "AX", h1)$status, "confirmed"))
mk3 <- fmut("ok <- identical(lk$status, \"resolved\") && hits(cl$clears_if_decision_matches, lk$decision)", "ok <- identical(lk$status, \"resolved\")")
chk2("MK3 해제 문구 대조 제거 돌연변이 → H1 red(Q④ 가 A 경로를 연다)", !is.null(mk3) && {
  hreg("Q④(C1 possible)로 분류 — 기전 반증 시도(mechanism_only)")
  isTRUE(tryCatch(mk3$rfv_prereg_gate(HR, PG, EXPO, "possible", BX)$ready, error = function(e) TRUE)) })
mk4 <- fmut("if (!fresh) { stale <- c(stale, paste0(basename(f), \":artifact_changed\")); next }", "if (FALSE) next")
chk2("MK4 stale 대조 제거 돌연변이 → Q17 red(바뀐 산출물의 기록이 살아남는다)", !is.null(mk4) && isTRUE(mk4$rfv_determinism_load(QR, DTC, "F1", dq$floors$F1$spec, QR)$determinism_ok))

# ═══ R 읽기 전용 ═══
cat("\n[R] 읽기 전용\n")
chk(identical(md5_prod(), PROD0), "R1 루트 지문 불변")
chk(identical(sort(list.files(file.path(ROOT, "06_Registry/prereg"))), PRE0), "R2 루트 prereg 폴더 불변")
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
