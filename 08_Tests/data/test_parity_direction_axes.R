# test_parity_direction_axes.R — benchmark_source_parity 방향 판정 축 위반 주입
#   신설 2026-08-20 (증거축 (c) close_reproducible 도입과 동반)
#
# 무엇을 지키는가:
#   이 판정기는 "두 소스가 갈렸을 때 **어느 쪽이 오염인가**"를 답한다. 그 답이 틀리면
#   수리기(repair_rawdata_bmret_from_benchmark.R)가 **정상 소스를 오염값으로 덮어쓴다**
#   — 경보는 맞는데 처방이 거꾸로인 상태(2026-08-08 주석의 실사고).
#
# ★★가장 중요한 불변식 = **축 순서**.
#   (c) close_reproducible 은 "benchmark 의 BM_Ret 이 자기 BM_Close 로 재현되는가"를 본다.
#   그런데 benchmark 가 스케일 단절로 오염된 경우 BM_Close 에도 같은 단절이 있어
#   **재현은 된다** → (c) 만 보면 "benchmark 정상"으로 뒤집힌다.
#   그래서 (a) value_plausibility 가 반드시 먼저 와야 한다. T4 가 그 순서를 박제한다.
#
# 실행: Rscript 08_Tests/data/test_parity_direction_axes.R

suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
suppressWarnings(suppressMessages(source("02_Infrastructure/validation/benchmark_source_parity.R")))

PASS <- 0L; FAIL <- 0L
chk <- function(n, c_, d = "") {
  if (isTRUE(c_)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", n)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", n, d)) }
}
TD <- file.path(tempdir(), "parity_axes"); dir.create(TD, recursive = TRUE, showWarnings = FALSE)

# 픽스처 생성기: 종가 시계열 -> (benchmark, RAWDATA) 한 쌍.
#   bench_ret_override / raw_ret_override 로 특정 날짜에 위반을 주입한다.
mk <- function(tag, closes, bench_override = list(), raw_override = list(), raw_closes = NULL) {
  dts <- seq(as.Date("2026-01-05"), by = "day", length.out = length(closes))
  bret <- c(NA_real_, head(closes, -1)); bret <- closes / bret - 1
  rc   <- if (is.null(raw_closes)) closes else raw_closes
  rret <- c(NA_real_, head(rc, -1)); rret <- rc / rret - 1
  b <- data.table(Date = dts, BM_Close = closes, BM_Ret = bret)
  r <- data.table(Date = dts, BM_Ret = rret)
  for (i in names(bench_override)) b[Date == as.Date(i), BM_Ret := bench_override[[i]]]
  for (i in names(raw_override))   r[Date == as.Date(i), BM_Ret := raw_override[[i]]]
  # RAWDATA 는 Ticker 축이 있으나 판정기는 unique(Date, BM_Ret) 만 본다
  bp <- file.path(TD, paste0("b_", tag, ".parquet")); rp <- file.path(TD, paste0("r_", tag, ".parquet"))
  write_parquet(b, bp); write_parquet(r, rp)
  list(b = bp, r = rp)
}
dirs_of <- function(f) {
  p <- benchmark_source_parity(rawdata_path = f$r, bench_path = f$b)
  if (is.null(p$repair_directions)) return(data.table())
  as.data.table(p$repair_directions)
}
CL <- 1000 * cumprod(c(1, rep(1.001, 9)))   # 완만한 10일 시계열

cat("=== 양성 대조 (판정기가 상시-발화가 아님) ===\n")
d <- dirs_of(mk("clean", CL))
chk("P1 두 소스 동일 -> 불일치 0건", nrow(d) == 0L, sprintf("(n=%d)", nrow(d)))

cat("\n=== 주입 (c) — RAWDATA 가 close 로 재현 안 됨 ===\n")
d <- dirs_of(mk("c_raw", CL, raw_override = list("2026-01-08" = -0.28)))
row <- d[Date == as.Date("2026-01-08")]
chk("C1 RAWDATA 오염으로 판정", nrow(row) == 1L && row$contaminated == "RAWDATA::BM_Ret",
    sprintf("(%s)", if (nrow(row)) row$contaminated else "행 없음"))
chk("C2 증거축이 close_reproducible", nrow(row) == 1L && row$evidence == "close_reproducible",
    sprintf("(%s)", if (nrow(row)) row$evidence else "-"))

cat("\n=== 주입 (c) — benchmark 의 BM_Ret 이 자기 close 와 어긋남 ===\n")
d <- dirs_of(mk("c_bench", CL, bench_override = list("2026-01-08" = 0.05)))
row <- d[Date == as.Date("2026-01-08")]
chk("C3 benchmark 오염으로 판정 (반대 방향도 잡힘)",
    nrow(row) == 1L && row$contaminated == "benchmark.parquet",
    sprintf("(%s)", if (nrow(row)) row$contaminated else "행 없음"))

cat("\n=== ★T4 축 순서 — 스케일 단절은 (a) 가 먼저 잡아야 한다 ===\n")
# benchmark 자체가 단절: close 를 통째로 무너뜨리면 BM_Ret 은 close 로 '재현은 된다'.
#   benchmark 만 단절시키고 RAWDATA 는 정상 종가에서 파생 -> 두 소스가 갈린다.
#   이때 benchmark 의 BM_Ret 은 자기 (단절된) close 로 **재현은 된다** — (c) 단독이면
#   "benchmark 정상 / RAWDATA 오염" 으로 뒤집힌다. (a) 가 먼저여야 막힌다.
CL_break <- CL; CL_break[8:10] <- CL_break[8:10] * 0.1      # -90% 스케일 단절
f <- mk("order", CL_break, raw_closes = CL)
d <- dirs_of(f)
brk <- as.Date("2026-01-12")                                 # 단절 첫날 (8번째 = 01-12)
row <- d[Date == brk]
chk("T4a 단절일이 판정 대상에 오름", nrow(row) == 1L, sprintf("(n=%d, dates=%s)", nrow(d),
    paste(format(d$Date), collapse=",")))
if (nrow(row) == 1L) {
  chk("T4b ★(c) 로 'RAWDATA 오염' 으로 뒤집히지 않음 (축 순서 불변식)",
      row$contaminated != "RAWDATA::BM_Ret", sprintf("(%s)", row$contaminated))
  chk("T4c 증거축이 value_plausibility (a 가 먼저 발화)",
      row$evidence == "value_plausibility", sprintf("(%s)", row$evidence))
}

cat("\n=== zero_masked 축이 살아있는가 (기존 축 회귀) ===\n")
d <- dirs_of(mk("zero", CL, raw_override = list("2026-01-08" = 0)))
row <- d[Date == as.Date("2026-01-08")]
chk("Z1 RAWDATA 0-위장 -> RAWDATA 오염", nrow(row) == 1L && row$contaminated == "RAWDATA::BM_Ret", "")
chk("Z2 증거축이 zero_masked (close 축에 삼켜지지 않음)",
    nrow(row) == 1L && row$evidence == "zero_masked",
    sprintf("(%s)", if (nrow(row)) row$evidence else "-"))

cat("\n=== BM_Close 부재 시 (축 비가용) ===\n")
dts <- seq(as.Date("2026-01-05"), by = "day", length.out = 10L)
bret <- c(NA_real_, head(CL, -1)); bret <- CL / bret - 1
bp <- file.path(TD, "b_noclose.parquet"); rp <- file.path(TD, "r_noclose.parquet")
write_parquet(data.table(Date = dts, BM_Ret = bret), bp)
rr <- data.table(Date = dts, BM_Ret = bret); rr[Date == as.Date("2026-01-08"), BM_Ret := -0.02]
write_parquet(rr, rp)
d <- dirs_of(list(b = bp, r = rp))
row <- d[Date == as.Date("2026-01-08")]
chk("N1 BM_Close 없으면 undetermined 로 남는다 (추측 금지)",
    nrow(row) == 1L && is.na(row$contaminated) && row$evidence == "undetermined",
    sprintf("(%s/%s)", if (nrow(row)) row$contaminated else "-", if (nrow(row)) row$evidence else "-"))

unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== test_parity_direction_axes: %d PASS / %d FAIL ===\n", PASS, FAIL))
cat(sprintf('{"test":"parity_direction_axes","pass":%d,"fail":%d,"skipped":0,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
