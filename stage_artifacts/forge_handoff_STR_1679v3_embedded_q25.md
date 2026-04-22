# STR_1679v3 embedded_q25 — Scout Handoff Kit (Forge용)

**작성**: Scout (Session 68 Day 2)  
**목적**: STR_1679v2 DROP 이후 v3 재설계. Forge Task #11 (factor_engine.R 초안 전달).  
**근거**: Q-Lead rev-v4 지시 + L-153/155 3-variant 교훈 + S3 TDC_lower 0.619 FAIL 경보.

---

## 왜 v3인가 (v2 DROP 원인)

| v2 문제 | v3 해결 방향 |
|---------|------------|
| Defense sleeve (Q07+D29) COSMETIC — standalone SR 0.21, MDD 65.3% | Q25_Ohlson_O embedded: 하방 노출 그 자체를 줄이는 signal |
| Overlay가 유일한 MDD lever (22.6pp 전담) | 팩터 시그널 레벨에서 downside protection 내재화 |
| STR_1631 TDC_lower 0.619 → Gate11 FAIL | C19 비중 축소 + Q25 embedding으로 구조적 분리 |
| Overlay 의존성 → DIVERSIFIER_WITH_OVERLAY_DEPENDENCY 판정 | S1 순수 신호 검증 (Overlay NONE) |

---

## STR_1679v3 설계 명세

### 핵심 아이디어
**"Earnings Composite + Downside Quality Embedded Blend"**

Q25_Ohlson_O (부실 가능성 낮은 기업 — Ohlson O-score 역전) 신호를 C19에 직접 embedded하여 하방 위험 종목을 시그널 레벨에서 필터링. Defense sleeve 물리 분리 없음 → TDC 구조적 개선.

### 팩터 구성
```
signal = 0.55 * z_C19 + 0.30 * z_Q25_inv + 0.15 * z_Q07
```

- **C19_Composite_Earnings** (0.55): Primary alpha source (v2 Core15와 동일 계열, 비중 축소)
- **Q25_Ohlson_O** (0.30, **반전**: 낮은 값 = 부실 위험 낮음): 하방 필터 embedded
  - Q25 recent_3y_icir=0.633, ic_bad=0.033 — 위기 시 IC 유지
  - **방향 주의**: Q25_Ohlson_O는 높을수록 부실 위험 HIGH → Z_Score_Aligned 후 부호 반전 필요
  - C13 준수: NEGATE_FACTORS 금지. `z_Q25_inv = -1 * Z_Score_Aligned(Q25)` 명시적 반전
- **Q07_Earnings_Stability** (0.15): 수익 안정성 보조 신호
  - Q07 recent_3y_icir=0.929 — 위기 안정성 탁월

### PIT 준수 체크리스트
- **C13**: Q25_Ohlson_O 반전 시 `z_Q25_inv <- -1 * z_Q25_aligned` 명시. NEGATE_FACTORS 사용 금지.
- **C15**: `load_month_factors(c("C19_Composite_Earnings", "Q25_Ohlson_O", "Q07_Earnings_Stability"))` 경유
- **C4**: Q25는 연간 재무제표 기반 → Usable_Date 경유 (5월 리밸런싱 또는 Usable_Date <= sig_date)
- **C14**: IC 계산 시 Usable_Date <= sig_date 필수
- **C1**: expanding IC window (IC_MIN_MONTHS = 24L 권장 — 3 factor composite)
- **C10**: 유동성 필터 20일 평균 거래대금 2억 lag=1

### 전략 파라미터
```r
N_HOLD         <- 20L
LIQ_THRESHOLD  <- 2e8
COMMISSION     <- 0.0015
REBAL_MONTHS   <- 2L   # v2와 동일
IC_MIN_MONTHS  <- 24L  # 3 factor composite → window 확대
# NO overlay (S1 순수 신호)
# NO physical sleeve 분리 (embedded blend)
```

### 예상 TDC 개선 논거
- C19 비중 v2(100% core) → v3(55%): Core15와 signal 구조 직접 분리
- Q25 반전 signal이 downside protection 내재화 → crisis 구간 공통 drawdown 감소
- Q07 추가로 earnings quality 기반 다각화
- 예상 TDC_lower vs STR_1631: 0.40~0.50 (v2 0.619에서 구조적 개선 목표)

### Forge factor_engine.R 핵심 코드 (초안)

```r
# STR_1679v3 factor_engine.R 초안 — Scout handoff

# Step 1: Factor DB 로드
req_factors <- c("C19_Composite_Earnings", "Q25_Ohlson_O", "Q07_Earnings_Stability")
factor_dt <- load_month_factors(req_factors)

# Step 2: Z_Score_Aligned 사용 (C13 준수)
# Q25_Ohlson_O: 높을수록 부실 위험 HIGH → 반전 필수
# 반전 방법: z-score 후 부호 반전 (C13: NEGATE_FACTORS 금지, 명시적 곱셈만)
factor_dt[, z_C19  := Z_Score_Aligned(C19_Composite_Earnings), by = Date]
factor_dt[, z_Q25  := Z_Score_Aligned(Q25_Ohlson_O), by = Date]
factor_dt[, z_Q25_inv := -1.0 * z_Q25]  # Ohlson_O 낮을수록 양호 → 반전
factor_dt[, z_Q07  := Z_Score_Aligned(Q07_Earnings_Stability), by = Date]

# Step 3: Composite signal
factor_dt[, signal := 0.55 * z_C19 + 0.30 * z_Q25_inv + 0.15 * z_Q07]

# Step 4: expanding IC (C1 준수)
# IC는 Usable_Date <= sig_date 기준 (C14)
# 팩터 방향 확인: signal 높을수록 양호 종목

# Step 5: Top N_HOLD selection (EW)
# 유동성 필터 후 signal 상위 20종목
```

---

## Forge 실행 지침 (Task #11)

1. `04_Research/strategies/STR_1679v3_embedded_q25/` 폴더 신규 생성
2. `run_all.R` 표준 헤더 작성:
   ```r
   cat("=== STR_1679v3: Earnings+Ohlson Quality Embedded Blend (C19+Q25_inv+Q07) ===\n")
   ## 핵심아이디어: C19 earnings composite + Q25 Ohlson downside quality embedded (no physical sleeve)
   ## v2 DROP 이유: Defense COSMETIC, Overlay 의존 → v3: signal-level downside protection
   ```
3. **Codex PIT flag 필수**: Forge 실행 전 `/tmp/codex_pit_approved_STR_1679v3_embedded_q25.flag` 생성 (forge_code_guard.sh 요건)
4. Q25 반전 명시적 코딩 (`z_Q25_inv <- -1.0 * z_Q25`) — C13 NEGATE 금지
5. 표준 hurdle_gate.R + tail_risk_engine.R 호출

---

## 성공 기준 (S1 검증)

| 항목 | 목표 | 판단 |
|------|------|------|
| ICIR | ≥ 0.20 | Alpha Lab Gate |
| TDC_lower vs STR_1631 | < 0.50 | Gate11 PASS |
| MDD (no overlay) | < 45% | hard_fail 회피 |
| SR | ≥ 0.8 | diversifier 역할 |
| Q25 반전 방향 확인 | ic_Q25_inv > 0 | C13 검증 |

---

## 관련 artifacts
- `stage_artifacts/s3_orthogonality_H_1693_partial.json` — TDC 기준선 (STR_1631 vs STR_1679v2 = 0.619)
- `stage_artifacts/judge_role_honesty_STR_1679v2_rerun.json` — v2 DROP 근거
- `.cache/conditional_ic_matrix.csv` — Q25 ic_bad=0.033, Q07 ic_bad=0.031
