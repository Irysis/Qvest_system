#!/usr/bin/env Rscript
#==============================================================================
# test_rf_carry_treatment.R — 승계(carry) 처치 전달 계약 **양방향 검사** (2026-08-31)
#
# 왜 이 검사가 있는가 (실사고):
#   승격 entry 는 부모 승자 구성을 carry 로 물려받고 그 위에 셀 처치를 얹는다. 그런데
#   병합이 단순 연결(c(carry$factors, cur))이라 **같은 팩터가 두 번** 들어갈 수 있었다.
#   스코어는 rowMeans(zb, z1, z2, ...) 등가중이므로 팩터가 하나 늘 때마다 **기저 신호
#   가중이 조용히 깎인다**(1/2 -> 1/3). 실측 2026-08-31:
#     부모 B3_12 factors=[Amihud]          PORT_t 2.63
#     자식 B3_12 factors=[Amihud, Amihud]  PORT_t 2.251   (기저 캐시 md5 동일 — 데이터 변화 아님)
#   그 결과 ①승계가 물려받은 구성을 희석해 promote 조건(부모 최고 초과)이 원리상 만족
#   불가능해지고 ②carry 와 같아진 칸(B1_5·B3_12·B4_18 이 소수 셋째 자리까지 동일)이
#   블록 승자가 되어 B2~B4 가 전부 그 위에 섰다.
#   B3_11(all_listed)과 같은 병이지만 이쪽은 **수치가 나오므로** 가드가 없으면 조용하다.
#
# 판정 축:
#   ① 중복 팩터가 제거되는가 (기저 가중 보존)
#   ② 서로 다른 팩터는 보존되는가 (음성 대조 — 고쳐서 반대쪽을 죽이지 않았는지)
#   ③ carry 와 동일한 구성이 무처치로 판정되는가
#   ④ 축 하나라도 다르면 처치로 판정되는가 (과잉 차단 금지)
#   ⑤ 러너 2종이 같은 규칙을 쓰는가 (한쪽만 고치면 경로에 따라 결과가 갈린다)
#   ⑥ spec 경로에 entry 식별자가 들어가는가 (부모 스펙 덮어쓰기 = 사후 재현 불가)
#
# ★헬퍼는 러너 소스에서 **추출해** 돌린다 — 사본 재구현은 러너가 바뀔 때 옛 규칙을 지키며 통과한다.
# 실행: Rscript 08_Tests/reinforcement/test_rf_carry_treatment.R   (부작용 없음)
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
PAR <- Sys.getenv("QVEST_RF_RUNNER", file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"))
SEQ <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_run.R")

PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }

# ── 러너에서 헬퍼 4종을 추출해 이 환경에 정의 ────────────────────────────────
src <- readLines(PAR, warn = FALSE)
# ★정본 경로를 덮을 수 있게 둔다 — 이 검사의 **양성 대조**(구판 헬퍼 주입)를 공유 정본을
#   건드리지 않고 돌리기 위해서다. 2026-09-03 헬퍼가 러너에서 이 파일로 옮겨갔는데
#   프로브는 러너에 주입하고 있어 양성 대조 둘이 하루 동안 죽어 있었다(축을 옮기면 대조도 옮길 것).
SIG <- Sys.getenv("QVEST_RF_SIG", file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
# ★2026-09-03: 헬퍼가 러너 인라인에서 정본 파일로 이동 — 사본 대신 정본을 source 한다.
if (!file.exists(SIG)) { cat("  FAIL 서명 정본 rf_spec_sig.R 부재\n"); quit(status = 1) }
suppressMessages(source(SIG))
cat("=== 헬퍼 = rf_spec_sig.R 정본 ===\n")

AMI <- list(kind = "db", id = "L01_Amihud")
BM  <- list(kind = "db", id = "V01_BM")

cat("=== 1. 중복 팩터 제거 (기저 가중 보존) ===\n")
r <- .dedup_factors(list(AMI, AMI))
if (length(r) == 1L) ok("[Amihud, Amihud] -> 1개") else ng("중복이 남았다", as.character(length(r)))
r3 <- .dedup_factors(list(AMI, AMI, AMI))
if (length(r3) == 1L) ok("3중복 -> 1개") else ng("3중복 처리", as.character(length(r3)))

cat("=== 2. 서로 다른 팩터는 보존 (음성 대조) ===\n")
r <- .dedup_factors(list(AMI, BM))
if (length(r) == 2L) ok("[Amihud, B/M] -> 2개 유지") else ng("다른 팩터를 지웠다", as.character(length(r)))
if (identical(.fkey(r[[1]]), "db:L01_Amihud")) ok("순서·식별자 보존") else ng("식별자 변형", .fkey(r[[1]]))

cat("=== 3. carry 와 동일 = 무처치 판정 ===\n")
carry <- list(factors = list(AMI), weighting = list(kind = "ew"),
              universe = list(kind = "index", flag = "K200"))
same <- identical(.fkeys(.dedup_factors(list(AMI, AMI))), .fkeys(carry$factors)) &&
        .same_axis(list(kind = "ew"), carry$weighting) &&
        .same_axis(list(kind = "index", flag = "K200"), carry$universe)
if (isTRUE(same)) ok("B1_5/B3_12 형태(전 축 동일) -> 무처치") else ng("무처치를 못 잡았다")

cat("=== 4. 축 하나라도 다르면 처치 (과잉 차단 금지) ===\n")
chk <- function(f, w, u) identical(.fkeys(.dedup_factors(f)), .fkeys(carry$factors)) &&
                         .same_axis(w, carry$weighting) && .same_axis(u, carry$universe)
if (!chk(list(AMI, BM), list(kind = "ew"), carry$universe)) ok("팩터가 다르면 처치로 판정") else ng("팩터 차이를 무처치로 봤다")
if (!chk(list(AMI), list(kind = "catalog", catalog_id = "lean:entropy"), carry$universe))
  ok("비중이 다르면 처치로 판정") else ng("비중 차이를 무처치로 봤다")
if (!chk(list(AMI), list(kind = "ew"), list(kind = "index", flag = "KQ150")))
  ok("유니버스가 다르면 처치로 판정") else ng("유니버스 차이를 무처치로 봤다")
if (!chk(list(AMI), list(kind = "ew"), list(kind = "size_band", q_lo = 0, q_hi = 0.3333)))
  ok("size_band 는 처치로 판정") else ng("size_band 를 무처치로 봤다")

cat("=== 4b. 오버레이 칸은 무처치가 아니다 (조립 순서) ===\n")
# ★2026-08-31 실사고: .no_treatment 를 carry 병합 블록 안에서 쟀는데, B5 는 그 **뒤에**
#   overlay 를 붙인다. 판정 시점엔 세 축이 carry 와 같아 다섯 칸이 전부 "무처치" 로 닫혔고
#   측정 0건으로 25 소진이 찍혀 다음 논문으로 넘어갔다. 계기가 재려는 것(처치가 있나)이
#   아니라 재기 쉬운 것(그 시점의 세 축)을 쟀다. 순서가 판정 축이다.
for (f in c(PAR, SEQ)) {
  L  <- readLines(f, warn = FALSE)
  # ★RHS 를 리터럴로 박지 않는다 — 2026-09-03 중첩(.ov_stack) 도입 때 이 줄이 낡아
  #   불변(순서)은 멀쩡한데 검사만 빨개졌다. 재는 것은 "B5 의 overlay 대입 위치" 다.
  io <- grep("SPEC$overlay <- ", L, fixed = TRUE)
  io <- io[grepl("CELL$overlay", L[io], fixed = TRUE)]
  ij <- grep("\\.no_treatment <- (identical\\(|rf_axes_same_as_carry\\()", L)   # ★B4-SIX(2026-09-26) 병렬 러너 판정식 = 등록부 함수
  if (length(io) && length(ij) && ij[1] > io[1])
    ok(sprintf("%s — 무처치 판정이 overlay 설정 뒤", basename(f))) else
    ng(sprintf("%s — 판정이 overlay 앞", basename(f)), "B5 가 측정 없이 닫힌다")
}
## ★B4-SIX-AXIS(2026-09-26): 병렬 러너 판정식 = 축 등록부(rf_spec_axes.R::rf_axes_same_as_carry) — 줄 대신 행동으로 잰다:
##   전 축 같으면 무처치 · 오버레이만 다르면 처치 · 등록부에 overlay 축이 있다. 순차 러너(퇴역 · 리터럴 판정식)는 구판 검사 그대로.
.AXF <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_axes.R")
for (f in c(PAR, SEQ)) {
  b <- paste(sub("#.*$", "", readLines(f, warn = FALSE)), collapse = "\n")
  if (grepl("rf_axes_same_as_carry(SPEC, E$carry)", b, fixed = TRUE)) {
    AE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(.AXF, envir = AE)))
    cy <- list(factors = list(AMI), weighting = list(kind = "ew"), universe = list(kind = "index", flag = "K200"))
    s_ov <- c(cy, list(overlay = list(kind = "dd_brake", arm_id = "x")))
    okb <- isTRUE(AE$rf_axes_same_as_carry(cy, cy)) && !isTRUE(AE$rf_axes_same_as_carry(s_ov, cy)) && "overlay" %in% AE$rf_axes_names()
    if (okb) ok(sprintf("%s — 판정식(등록부)에 overlay 축 포함 · 오버레이만 다른 칸 = 처치", basename(f))) else
      ng(sprintf("%s — 등록부 판정식이 overlay 를 처치로 안 센다", basename(f)), "오버레이가 처치로 안 세어진다")
  } else if (grepl("SPEC$overlay,   E$carry$overlay", b, fixed = TRUE))
    ok(sprintf("%s — 판정식에 overlay 축 포함", basename(f))) else
    ng(sprintf("%s — 판정식에 overlay 없음", basename(f)), "오버레이가 처치로 안 세어진다")
}

cat("=== 5. 러너 2종이 같은 규칙 ===\n")
bp <- paste(sub("#.*$", "", src), collapse = "\n")
bs <- paste(sub("#.*$", "", readLines(SEQ, warn = FALSE)), collapse = "\n")
for (nm in c("dedup_factors", "no_treatment")) {
  hit <- grepl(nm, bp, fixed = TRUE) && grepl(nm, bs, fixed = TRUE)
  if (hit) ok(sprintf("%s — 병렬·순차 양쪽 배선", nm)) else
    ng(sprintf("%s 한쪽만 배선", nm), "경로에 따라 결과가 갈린다")
}
# 무처치 칸이 measurement 없이 닫히는가 (성공 위장 금지)
if (grepl("cell_no_treatment", bp, fixed = TRUE) && grepl("cell_no_treatment", bs, fixed = TRUE))
  ok("무처치 칸을 로그로 드러낸다(침묵 스킵 아님)") else ng("무처치가 조용히 지나간다")

cat("=== 6. spec 경로에 entry 식별자 (부모 재현 가능성) ===\n")
if (grepl('spec_%s__%s.json', bp, fixed = TRUE)) ok("병렬 spec 경로에 base_id") else
  ng("병렬 spec 이 고정 이름", "다음 entry 가 덮어써 부모 스펙이 소실된다")
if (grepl('rf_cell_spec_%s__%s.json', bs, fixed = TRUE)) ok("순차 spec 경로에 base_id") else
  ng("순차 spec 이 고정 이름", "같은 덮어쓰기")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_carry_treatment","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
