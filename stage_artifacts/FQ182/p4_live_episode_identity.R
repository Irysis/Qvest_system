## FQ-182 P4 — ★live 에피소드 정체 검사 (존재 검사 전에 정체 검사)
## 혐의: 적대검증이 "효과의 31~43%가 2026-07-08~08-06 live 미완결 에피소드에서 나온다" 고 했다.
##   그런데 **오늘(2026-08-09) 벤치 2026 구간에 이음매 결함이 수리**됐다
##   (memory: project-walking-seam-defect-date-pinned-repair-fails-20260809 —
##    벤치 2026 −81.8% vs 참값 +60.85%, cutoff 가 매일 전진해 재발, alpha_search 16/466 run 오염).
##   내 RAWDATA BM_Ret 이 그 결함 또는 부분수리 상태라면 live 에피소드는 **쓰레기**다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
say("=== 1. 내 패널의 2026 구간 정체 ===")
Y <- D[, .(n = .N, mean = mean(BM_Ret), sd = sd(BM_Ret),
           cum = prod(1 + BM_Ret) - 1, min = min(BM_Ret), max = max(BM_Ret)),
       by = .(yr = format(Date, "%Y"))][order(yr)]
print(tail(Y, 6))
say("  ★메모리 기록: 벤치 2026 이 **−81.8%%** 로 나오던 결함(참값 +60.85%%)이 오늘 수리됨")
y26 <- Y[yr == "2026"]
say("  내 패널 2026 누적수익 = %+.4f (%.1f%%)", y26$cum, y26$cum*100)
say("  ⇒ %s", if (y26$cum < -0.5) "★★결함값(-81.8%대) — 데이터 오염 확정" else
             if (y26$cum > 0.3) "수리된 값(+60%대)에 가까움" else "중간값 — 추가 확인 필요")

say("=== 2. RAWDATA 원본 재확인 (내 p0.rds 캐시가 오래됐을 수 있다) ===")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","BM_Ret")))
RAW[, Date := as.Date(Date)]
BD <- unique(RAW[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
say("  RAWDATA 현재: %d일 · 최종 %s", nrow(BD), max(BD$Date))
B26 <- BD[Date >= as.Date("2026-01-01")]
say("  RAWDATA 2026: %d일 · 누적 %+.4f (%.1f%%)", nrow(B26), prod(1+B26$BM_Ret)-1, (prod(1+B26$BM_Ret)-1)*100)
say("  내 캐시 2026 누적 %+.4f vs RAWDATA 현재 %+.4f · 차이 %+.5f",
    y26$cum, prod(1+B26$BM_Ret)-1, y26$cum - (prod(1+B26$BM_Ret)-1))
say("  ⇒ %s", if (abs(y26$cum - (prod(1+B26$BM_Ret)-1)) > 1e-6)
    "★★캐시와 원본이 다르다 — 내 측정은 낡은(수리 전) 데이터 위에서 이뤄졌다" else "캐시=원본 일치")

say("=== 3. live 에피소드(2026-07-08~08-06) 정체 ===")
L <- D[Date >= as.Date("2026-07-01")]
say("  기간 %s ~ %s · %d일", min(L$Date), max(L$Date), nrow(L))
say("  dd252 범위 %.4f ~ %.4f · 수익 범위 %.4f ~ %.4f", min(L$dd252), max(L$dd252),
    min(L$BM_Ret), max(L$BM_Ret))
say("  dd252 <= -20%% 인 날: %d일 · <= -30%%: %d일", sum(L$dd252 <= -0.20), sum(L$dd252 <= -0.30))
say("  ★상위 |수익| 5일:")
for (i in order(-abs(L$BM_Ret))[1:min(5,nrow(L))])
  say("    %s  BM_Ret %+.4f · dd252 %.4f", L$Date[i], L$BM_Ret[i], L$dd252[i])

say("=== 4. ★물리적 타당성 — 일간 수익이 현실적인가 ===")
ext <- D[abs(BM_Ret) > 0.10]
say("  |일수익| > 10%% 인 날 %d개:", nrow(ext))
if (nrow(ext)) for (i in seq_len(min(12, nrow(ext))))
  say("    %s  %+.4f", ext$Date[i], ext$BM_Ret[i])
say("  ★KR 시장 일간 상하한은 ±30%%(2015~) / ±15%%(이전). 그 밖 값은 데이터 결함 의심.")

say("=== 5. 판정 ===")
stale <- abs(y26$cum - (prod(1+B26$BM_Ret)-1)) > 1e-6
bad26 <- y26$cum < -0.5
say("  캐시 낡음: %s · 2026 결함값: %s", stale, bad26)
say("  ⇒ %s", if (stale || bad26)
  "★★live 에피소드 기여 수치는 오염 데이터 위 값 — 적대검증 결론 재검 필요" else
  "데이터 정합 — live 에피소드 의존은 실재하는 취약성")
saveRDS(list(yearly = Y, live = L, stale = stale, bad26 = bad26), file.path(OUT, "p4.rds"))
say("=== P4 완료 ===")
