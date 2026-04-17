---
name: s1-factor-construction
description: "S1 팩터 코드 작성 시 적용 — run_all.R 표준, 순수 팩터, PIT 준수"
hooks:
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: "command"
          if: "Write(*.R)|Edit(*.R)"
          command: "DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1); bash \"$DIR/02_Infrastructure/hooks/forge_code_guard.sh\""
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: "agent"
          if: "Bash(Rscript*source*run_all*)"
          prompt: "백테스트 완료. output 디렉토리에서 tail_risk_result.json 존재 확인. 없으면 {\"ok\":false, \"reason\":\"tail_risk 미측정\"}, 있으면 {\"ok\":true}."
          timeout: 60
---
## S1 팩터 구축 규칙

### 순수 팩터만 (S1 철칙)
- DD/VT/Regime 오버레이 **절대 금지**
- EW 20종목 + 15bps commission + 유동성 필터(20일 평균 거래대금 ≥ 2억원)

### run_all.R 표준 헤더
```r
cat("=== STR_XXX: 설명 ===\n")
## 핵심아이디어: 1줄 설명
## 참조논문: core_reference
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
```

### 실행 패턴
`cd strategy_dir && Rscript -e 'source("run_all.R")'` (--file= 금지, 한글 경로)

### 속도 최적화
```r
setkey(dt, Date, Ticker)                    # 모든 merge 전
load_rawdata(use_cache = TRUE)              # RAWDATA 1회만
frollmean(x, 20); frollsum(x, 20)          # C 구현 롤링
open_dataset(".cache/factor_db") |> filter(Date == sig_d) |> collect()  # predicate pushdown
```

### 분석 기간 (Level 0)
- **날짜 하드코딩 절대 금지**: `as.Date("2004-...")`, `as.Date("2005-...")` 직접 기입 금지
- config.R의 글로벌 상수 사용 필수:
  - `ANALYSIS_START_DATE` (1990-01-01) — RAWDATA/BM 로드 범위
  - `SIGNAL_START_DATE` (1990-07-01) — 시그널 생성 시작일
- Factor DB `load_month_factors()`는 데이터 없는 구간 자동 NA 처리
- Consensus 데이터는 ~2000년부터 존재, 이전 구간은 자연 필터링

### Regime Overlay PIT 규칙 (C5)
- `regime_engine_daily.R`의 `build_daily_regime()`이 반환하는 MRS는 **이미 t-1 lagged**
  - Step 5 (line 339): `dt[, MRS := shift(MRS_raw, n = 1L, type = "lag")]`
  - MRS[t] = MRS_raw[t-1] — 오늘의 MRS는 어제 데이터로 계산된 값
- **overlay 코드에서 MRS에 추가 shift() 금지** — 이중 lag → t-2 오류
- 대신 아래 PIT 주석을 overlay 코드에 반드시 포함:
```r
# PIT NOTE: MRS is already t-1 lagged in regime_engine_daily.R (Step 5, line 339).
# MRS[t] = MRS_raw[t-1]. No additional shift() needed — double-lag would create t-2 error.
```

### Factor DB 접근 (C13/C14/C15)
- `load_month_factors(sig_date)` 경유 필수 (C15)
- `Z_Score_Aligned`만 사용 (C13). 수동 방향 반전 금지.
- IC 접근 시 `Usable_Date <= sig_date` (C14)
