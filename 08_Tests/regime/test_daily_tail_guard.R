# test_daily_tail_guard.R -- 국면 일간 빌더의 꼬리 가드 (2026-11-10 전수점검)
#
# 지키는 것:
#   일간 척추는 층 날짜의 합집합이다. 벤치 기반 MSM(L1)만 새 거래일에 닿고 RAWDATA 기반 KTRI(L3)가 아직 안 닿은 날에도
#   행이 생기면, 그 행의 KTRI 는 LOCF 로 직전 값이 채워지고(Active_Layers 는 L1+L2+L3) 원장 병합이 첫 병합에서 동결한다 —
#   덜 온 입력으로 만든 행이 발행본에 영구히 남는다. 가드는 켜진 시장 자료 층이 모두 닿은 날까지만 행을 만든다.
#
# 계약(양방향):
#   A  [음성]   두 층 끝이 같으면 아무것도 자르지 않는다
#   B  [양성]   L1 이 앞서면 L3 끝 뒤 날짜를 자른다 — 남은 마지막 날은 KTRI 자기 관측이다
#   C  [양성]   L3 이 앞서도 같은 규칙(L1 끝 뒤를 자른다)
#   D  [음성]   한 층이 꺼져 있으면(allow_partial) 켜진 층의 끝이 기준이다
#   E  [위반 주입] 자르는 줄을 지운 사본은 B 를 통과하지 못한다(검사가 병을 본다)
#   F  [배선]   가드가 척추 조립과 base 생성 사이에 있다(LOCF 병합보다 앞)
#
# 방식: 소스에서 가드 블록을 그대로 꺼내 실행한다(재구현 금지). 파일 쓰기 없음.
# 실행: Rscript 08_Tests/regime/test_daily_tail_guard.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
emit <- function() cat(sprintf('{"test":"daily_tail_guard","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
done <- function() { emit(); if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L) }

SRC <- file.path(root, "02_Infrastructure", "regime", "regime_signal.R")
if (!file.exists(SRC)) { ng("regime_signal.R 부재"); done() } else {
  lines <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
  i0 <- grep(".tail_ends <- as.Date(character(0))", lines, fixed = TRUE)
  i1 <- grep("base <- data.table(Date = all_dates)", lines, fixed = TRUE)
  iS <- grep('if (length(all_dates) == 0) stop("[regime_signal/daily] Empty date spine.")', lines, fixed = TRUE)
  iL <- grep('setnafill(base, type = "locf", cols = c("KTRI_Score", "VEA_Score"))', lines, fixed = TRUE)
  if (length(i0) != 1L || length(i1) < 1L) { ng("소스에서 가드 블록을 못 찾음(앵커 소실 — 검사가 대상을 잃음)"); done() } else {
    i1 <- i1[i1 > i0][1]
    BLOCK <- lines[i0:(i1 - 1L)]
    ok(sprintf("소스에서 가드 블록 %d줄 추출", length(BLOCK)))

    run_guard <- function(block, msm_dates, ktri_dates, l1_ok = TRUE, l3_ok = TRUE) {
      e <- new.env(parent = globalenv())
      e$msm_dt  <- data.frame(Date = as.Date(msm_dates))
      e$ktri_dt <- data.frame(Date = as.Date(ktri_dates))
      e$l1_ok <- l1_ok; e$l3_ok <- l3_ok; e$verbose <- FALSE
      # 빌더와 같은 모양(꺼진 층은 빈 Date) — c(NULL, Date) 는 Date 속성을 잃는다
      e$all_dates <- sort(unique(c(if (l1_ok) e$msm_dt$Date else as.Date(character(0)),
                                   if (l3_ok) e$ktri_dt$Date else as.Date(character(0)))))
      eval(parse(text = block), envir = e)
      stopifnot(inherits(e$all_dates, "Date"))
      e$all_dates
    }
    d <- as.Date(c("2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-09"))

    cat("== A 두 층 끝이 같다 ==\n")
    r <- run_guard(BLOCK, d, d)
    chk(identical(r, d), "A1 아무것도 자르지 않는다")

    cat("== B L1(벤치) 이 앞선다 — 11-10 아침 조건 ==\n")
    r <- run_guard(BLOCK, d, d[1:4])
    chk(identical(max(r), as.Date("2026-11-06")), "B1 척추 끝 = L3 끝(11-06)")
    chk(!(as.Date("2026-11-09") %in% r), "B2 미도달 날짜(11-09)는 행이 없다")
    chk(max(r) %in% d[1:4], "B3 남은 마지막 날의 KTRI 는 자기 관측이다(LOCF 아님)")

    cat("== C L3 이 앞선다 ==\n")
    r <- run_guard(BLOCK, d[1:3], d)
    chk(identical(max(r), as.Date("2026-11-05")), "C1 척추 끝 = L1 끝")

    cat("== D 한 층이 꺼짐 ==\n")
    r <- run_guard(BLOCK, d, character(0), l1_ok = TRUE, l3_ok = FALSE)
    chk(identical(r, d), "D1 L3 꺼짐 → L1 끝이 기준 · 자르지 않는다")
    r <- run_guard(BLOCK, character(0), d[1:4], l1_ok = FALSE, l3_ok = TRUE)
    chk(identical(r, d[1:4]), "D2 L1 꺼짐 → L3 끝이 기준")

    cat("== E 위반 주입 ==\n")
    j <- grep("all_dates <- all_dates[all_dates <= .tail_lim]", BLOCK, fixed = TRUE)
    chk(length(j) == 1L, "E0 돌연변이 대상 줄이 정확히 한 곳")
    if (length(j) == 1L) {
      MUT <- BLOCK; MUT[j] <- "      invisible(NULL)"
      chk(!any(grepl("all_dates <- all_dates[all_dates <= .tail_lim]", MUT, fixed = TRUE)), "E1 치환이 들어갔다")
      r <- run_guard(MUT, d, d[1:4])
      chk(as.Date("2026-11-09") %in% r, "E2 자르는 줄이 없으면 미도달 날짜가 남는다 — B2 가 이것을 잡는다")
    }

    cat("== F 배선 위치 ==\n")
    chk(length(iS) == 1L && iS < i0, "F1 가드는 척추 조립 뒤에 있다")
    chk(length(iL) >= 1L && i0 < min(iL), "F2 가드는 KTRI LOCF 병합보다 앞에 있다")
    done()
  }
}
