#!/usr/bin/env Rscript
# test_forward_parity.R — [P3 초안] parity 검사기 위반 주입 테스트 (양방향)
# 원칙: "FAIL 이 뜬다"만으로는 검사기 생존 증명이 안 된다. 정상 입력에 PASS, 위반 입력에 FAIL,
#       미세 섭동에 FAIL, 전제 부재에 ERROR(≠PASS) — 네 방향 전부 확인해야 한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
BASE <- "stage_artifacts/tilt_realign_20260808"
source(file.path(BASE, "forward_parity_check.R"))
TMP <- file.path(BASE, "_test_tmp"); dir.create(TMP, showWarnings = FALSE, recursive = TRUE)

AS_OF <- "2026-08-01"
DEPLOYED <- "05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe/20260801_M4gAE_weights_cap_0p20.csv"
STAGED   <- file.path(BASE, "output/20260801_M4gAE_weights_cap_0p20_v2staged.csv")

pass <- 0L; fail <- 0L
chk <- function(name, got, want) {
  ok <- identical(got, want)
  cat(sprintf("  [%s] %-52s got=%-5s want=%-5s\n", if (ok) "PASS" else "FAIL", name, got, want))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
}

cat("=== 1. 양성 대조 — 정본 규약으로 생성된 산출물은 PASS 여야 ===\n")
r1 <- forward_parity_check(STAGED, AS_OF, declared_convention = "canonical", verbose = TRUE)
chk("정본 산출물 × canonical 규약", r1$status, "PASS")

cat("\n=== 2. 위반 주입 — 실배포(z-선형) 산출물은 canonical 규약에서 FAIL 이어야 ===\n")
r2 <- forward_parity_check(DEPLOYED, AS_OF, declared_convention = "canonical", verbose = TRUE)
chk("실배포 산출물 × canonical 규약", r2$status, "FAIL")
cat(sprintf("       검출 괴리 = %.4f (%.1f%%) — 0 이면 검사기 무력\n", r2$divergence, r2$divergence*100))
chk("괴리가 유의미한 크기(>0.05)", r2$divergence > 0.05, TRUE)

cat("\n=== 3. 규약 파라미터 실효 — 같은 실배포 파일을 zlinear 규약으로 재면 PASS (결정-독립 증명) ===\n")
r3 <- forward_parity_check(DEPLOYED, AS_OF, declared_convention = "zlinear", verbose = TRUE)
chk("실배포 산출물 × zlinear 규약", r3$status, "PASS")

cat("\n=== 4. 미세 섭동 감도 — 정본 산출물의 1종목만 1e-4 흔들면 FAIL 이어야 ===\n")
mut <- fread(STAGED); i <- which(mut$Ticker != "CASH")[1]
mut$Weight[i] <- mut$Weight[i] + 1e-4
mp <- file.path(TMP, "mutated.csv"); fwrite(mut, mp)
r4 <- forward_parity_check(mp, AS_OF, declared_convention = "canonical", verbose = TRUE)
chk("1e-4 섭동 산출물", r4$status, "FAIL")

cat("\n=== 5. 전제 부재 — 파일 부재/0행은 PASS 가 아니라 ERROR 여야 ('빈 결과=합격' 차단) ===\n")
r5 <- forward_parity_check(file.path(TMP, "does_not_exist.csv"), AS_OF, verbose = TRUE)
chk("파일 부재", r5$status, "ERROR")
ep <- file.path(TMP, "empty.csv"); fwrite(data.table(rank=integer(), Ticker=character(), Weight=numeric()), ep)
r6 <- forward_parity_check(ep, AS_OF, verbose = TRUE)
chk("0행 CSV", r6$status, "ERROR")
cp <- file.path(TMP, "cash_only.csv"); fwrite(data.table(rank=0L, Ticker="CASH", Weight=1.0), cp)
r7 <- forward_parity_check(cp, AS_OF, verbose = TRUE)
chk("CASH 행만 존재(주식 0)", r7$status, "ERROR")

cat(sprintf("\n===== 결과: %d PASS / %d FAIL =====\n", pass, fail))
unlink(TMP, recursive = TRUE)
quit(status = if (fail == 0L) 0L else 1L)
