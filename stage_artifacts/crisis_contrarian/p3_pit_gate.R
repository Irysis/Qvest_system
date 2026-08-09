## 위기신호 역방향 — P3: ★PIT 관문 (주장 전 필수)
## 혐의: unified_regime_signal / msm_hybrid_latest 가 **전표본 재적합** 산물이면
##       'Crisis 라벨' 이 미래를 알고 켜진 것이고 forward +29%/yr 는 전부 무효다.
## 이 저장소는 같은 방식으로 3회 데였다(저장 패널 동월 look-ahead 2.08x · FRED vintage 미저장 · overlay 동월).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/crisis_contrarian")
say  <- function(fmt, ...) { cat(sprintf(paste0("[pit] ", fmt, "\n"), ...)); flush.console() }

say("=== 1. 산출 파일의 생성 시각·구조 ===")
for (p in c(".cache/unified_regime_signal.parquet", ".cache/msm_hybrid_latest.parquet",
            ".cache/regime_forecast_series.parquet", ".cache/macro_regime.parquet")) {
  if (!file.exists(p)) { say("  %s 부재", p); next }
  fi <- file.info(p)
  say("  %-46s mtime=%s  %.0f KB", p, format(fi$mtime, "%Y-%m-%d %H:%M"), fi$size/1024)
}
say("  ★단일 파일 + 'latest' 접미 = vintage 없음 시사. 과거 각 시점의 라벨이 보존돼 있지 않다면")
say("    현재 파일의 라벨은 **오늘 시점 재적합값**일 수 있다.")

say("=== 2. vintage/asof 디렉토리 존재 여부 ===")
for (d in c(".cache/regime_vintage", ".cache/vintage", ".cache/msm_vintage", ".cache/regime_history")) {
  say("  %-28s %s", d, dir.exists(d))
}
v <- list.files(".cache", pattern="vintage|asof|snapshot", full.names=TRUE)
say("  .cache 내 vintage/asof/snapshot 매칭: %d건 %s", length(v),
    if (length(v)) paste(head(basename(v),6), collapse=", ") else "")

say("=== 3. 생성 코드에서 전표본 적합 흔적 ===")
src <- c("02_Infrastructure/regime/regime_ensemble.R",
         "02_Infrastructure/regime/regime_engine_daily.R",
         "02_Infrastructure/regime/regime_forecaster.R")
for (s in src) {
  if (!file.exists(s)) { say("  %s 부재", s); next }
  L <- readLines(s, warn = FALSE)
  n_roll <- sum(grepl("rolling|expanding|walk.?forward|refit|window", L, ignore.case = TRUE))
  n_full <- sum(grepl("full.?sample|entire|all.?data|fit.*\\ball\\b", L, ignore.case = TRUE))
  n_msm  <- sum(grepl("MSwM|msmFit|HMM|depmix|markov", L, ignore.case = TRUE))
  say("  %-46s rolling/expanding %d · full-sample %d · MSM적합 %d", basename(s), n_roll, n_full, n_msm)
  hit <- grep("msmFit|depmix|MSwM|smooth|filtered|posterior", L, ignore.case = TRUE, value = TRUE)
  for (h in head(hit, 4)) say("      | %s", substr(trimws(h), 1, 118))
}

say("=== 4. ★결정적 지문: smoothed vs filtered ===")
say("  Markov-switching 에서 **smoothed 확률**은 전표본을 쓰므로 미래를 안다.")
say("  **filtered 확률**만 PIT-안전. 코드에 smooth/posterior 가 있고 filtered 가 없으면 look-ahead 확정.")

say("=== 5. 대안 검증(코드 무관) — 라벨이 미래를 아는지 행동으로 시험 ===")
say("  (a) 라벨 ON 이 **하락 직전**이 아니라 **하락 직후**에 몰린다 = 지연(정상, PIT 무해)")
say("  (b) 라벨 ON 이 **바닥 정확히 그 달**에만 몰린다 = smoothing 지문(look-ahead 의심)")
B <- readRDS(file.path(OUT, "p1_bench.rds"))$bench
setorder(B, Date); B[, ym := format(Date, "%Y-%m")]
B[, `:=`(lag1 = shift(BM_Ret,1L), lag2 = shift(BM_Ret,2L), f1 = shift(BM_Ret,1L,type="lead"))]
M <- as.data.table(read_parquet(".cache/msm_hybrid_latest.parquet"))
M[, ym := format(as.Date(Date), "%Y-%m")]
Z <- merge(B, M[, .(v = tail(Regime,1L)), by = ym], by = "ym")
on <- Z$v == "Crisis"
say("  msm Crisis(n=%d): 전월 %+.2f%% · 전전월 %+.2f%% · **당월 %+.2f%%** · 익월 %+.2f%% (월평균 연율)",
    sum(on, na.rm=TRUE),
    mean(Z$lag2[on], na.rm=TRUE)*12*100, mean(Z$lag1[on], na.rm=TRUE)*12*100,
    mean(Z$BM_Ret[on], na.rm=TRUE)*12*100, mean(Z$f1[on], na.rm=TRUE)*12*100)
say("  비-Crisis           : 전월 %+.2f%% · 전전월 %+.2f%% · 당월 %+.2f%% · 익월 %+.2f%%",
    mean(Z$lag2[!on], na.rm=TRUE)*12*100, mean(Z$lag1[!on], na.rm=TRUE)*12*100,
    mean(Z$BM_Ret[!on], na.rm=TRUE)*12*100, mean(Z$f1[!on], na.rm=TRUE)*12*100)
say("  ★해석: 라벨이 켜지기 **전**(lag1/lag2)이 크게 음수여야 '지연 반응' = PIT 무해.")
say("    전·당·익월이 모두 양수면 라벨이 상승 국면을 통째로 알고 있다는 뜻 = look-ahead 의심.")

saveRDS(list(z = Z), file.path(OUT, "p3_pit.rds"))
say("=== P3 완료 ===")
