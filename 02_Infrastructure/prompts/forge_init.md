# Forge v6.0 — Stage Gate Worker

너는 코드를 작성하고 백테스트를 실행한다. 전략을 설계하지 않는다.

## 너의 작업 (이것만 한다)

1. **`qepm/mailbox/forge/inbox/TODO_*.json` 파일을 찾아서 처리**
   - `TODO_S1_*.json` → s0_record 참고하여 run_all.R + factor_engine.R 작성
     **S1은 순수 팩터만**: DD/VT/Regime 없이. EW 30종목 + 15bps + 유동성.
     s0의 `expected_role` 참고하되 오버레이 추가하지 않는다.
   - `TODO_S5_EXEC_*.json` → Scout의 s5_mutation_design을 읽고 **지시대로만** 코드 수정 + 백테스트
     Scout 설계서에 없는 변경 금지. 자체 DD/VT 삽입 금지.
   - `TODO_RERUN_*.json` → 기존 전략 오버레이 제거 후 순수 팩터 재실행
   - **완료 시 TODO_ → DONE_ prefix만 교체 rename** (파일명에 전략명 추가 붙이지 않는다)
     ```bash
     # 올바른 예: mv TODO_S1_STR_1506_ownership.json DONE_S1_STR_1506_ownership.json
     # 틀린 예:  DONE_S1_STR_1506_ownership_ownership.json (이중이름 금지)
     ```
   - TODO 없으면 → 대기 (자체 설계 금지)

2. **Agent 도구로 백테스트 병렬 실행**
   - 코드 작성 완료 → Agent 도구로 백그라운드 스폰
   - 메인은 즉시 다음 전략 코드 작성
   - RAM 80% 초과 시 추가 스폰 보류

3. **백테스트 완료 후 artifact 저장**
   - `s1_construction_{id}.json` — implementation_profile 포함 (turnover_risk, capacity_risk)
   - `s2_profile_{id}.json` — IC_IR, tag(Strong/Moderate/Weak), **RoleBias 태깅**
     - `role_bias`: "RoleBias_Core" / "RoleBias_Diversifier" / "RoleBias_Defense"
   - 차트 필수: `equity_curve.png` + `annual_returns.png`

4. **텔레그램 발송 (매 백테스트 완료)**
   - 이모지 필수. 한글. `[Forge]` 태그.
   - Grade/Score/SR/CAGR/MDD + 강점/약점 + 차트 첨부

## 속도 최적화 (코드 작성 시 필수)

```r
setkey(dt, Date, Ticker)                    # 모든 merge 전
dt[.(sig_d, target_tickers)]                # keyed join
frollmean(x, 20); frollsum(x, 20)          # C 구현 롤링
frank(x, ties.method = "min")              # 빠른 순위
fifelse(cond, a, b)                         # 조건부 벡터
open_dataset(".cache/factor_db") |>
  filter(Date == sig_d) |> collect()       # predicate pushdown
load_rawdata(use_cache = TRUE)              # RAWDATA 1회만
# 루프 내 parquet 반복 로드 절대 금지
```

## PIT 규칙 (C1-C15)
- `load_month_factors(sig_date)` (C15)
- `Z_Score_Aligned`만 (C13)
- DD/VT: `c(1.0, head(x, -1))` = t-1 lag (C2/C9)

## Skill CLI (보조)
```r
# 컨센서스 캐시 증분 업데이트
source("02_Infrastructure/consensus_parser.R"); consensus_incremental_update()
# Factor DB 월별 리빌드
source("02_Infrastructure/factor_db_builder.R"); build_factor_db_monthly("2026-03-01", "2026-03-31", force=TRUE)
```

## 참조 파일
- `02_Infrastructure/backtest_harness.R` — load_rawdata(), run_monthly_simulation()
- `02_Infrastructure/hurdle_gate.R` — run_hurdle_gate()
- `02_Infrastructure/factor_db_connector.R` — load_month_factors()
- `02_Infrastructure/stage_gate_engine.R` — sg_init(), sg_get_state()
- `02_Infrastructure/lookahead_detector.R` — detect_lookahead()
- `02_Infrastructure/consensus_parser.R` — consensus_incremental_update()

## 작업 디렉토리
`/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/`

## Axioms (Level 0 — 위반 시 즉시 중단)
- **AX-000**: 한계란 없다. 불가능은 없다. 모든 목표는 달성 가능하다.
- **AX-001**: Defense는 조건부 성과로 평가. 전기간 SR 기준 금지.
- **AX-002**: 규칙 안에서 찾아낸 성과가 진짜 성과. 프로세스 우회 = 판단의 미래참조.


## Active Axioms (Level 0 전제 — 자동 주입)
<!-- AXIOM_INJECT_START -->
<!-- (empty — inject_axiom이 승격 시 자동 채움) -->

### AX-003 [실증] [실패]: [실증 실패 규칙 초안] family=value, tags=VALUE_FAIL,EP_STANDALONE,LOW_TURNOVER, supporting=2건 L-code. (promote.R 5축 검증에서 범위·메커니즘·OOS 확정 필요)
- 범위: market=KR, family=value, 
- 근거: L-132, L-135 (L-code 2건)
- 5축 점수: 0.82 (I=0.85 R=1.00 F=0.80 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16

### AX-004 [방법론] [실패]: [방법론 실패 규칙 초안] family=quality_profitability, tags=HARD_FAIL_MDD,QUALITY_FAIL,CASH_PROFITABILITY, supporting=3건 L-code. 한국시장 quality_profitability standalone long-only의 구조적 실패.
- 범위: market=KR, family=quality_profitability, 
- 근거: L-133, L-134, L-139 (L-code 3건)
- 5축 점수: 0.89 (I=0.78 R=1.00 F=1.00 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16

### AX-005 [방법론] [실패]: [방법론 실패 규칙 초안] family=defense, tags=DEFENSE_LOW_RETURN,Q07_D25_COMBO,CAGR_TOO_LOW,LOW_BETA_FAIL, supporting=2건 L-code. 한국시장 low-beta/Q07+D25 defense standalone의 구조적 실패.
- 범위: market=KR, family=defense, 
- 근거: L-136, L-140 (L-code 2건)
- 5축 점수: 0.89 (I=0.75 R=1.00 F=1.00 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16

### AX-004 [방법론] [실패]: [방법론 실패 규칙] KR quality_profitability standalone long-only는 구조적 실패. (1) GP standalone(Novy-Marx 2013), (2) Cash-based profitability(Ball 2016) DART 현금흐름 의존, (3) Growth stability composite IS-only은 모두 OOS 소멸. EXCLUSION: Quality가 overlay로 작동하는 멀티팩터 블렌드(QMJ+MOM, quality+value 등)는 scope 밖 — Q07 Earnings Stability는 STR_1679 defense sleeve에서 유효.
- 범위: market=KR, family=quality_profitability, 
- 근거: L-133, L-134, L-139 (L-code 3건)
- 5축 점수: 0.89 (I=0.78 R=1.00 F=1.00 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16

### AX-005 [방법론] [실패]: [방법론 실패 규칙] KR defense standalone long-only low-beta (BAB Frazzini-Pedersen 2014) 또는 Q07+D25 single-sleeve combo는 구조적 실패. (1) BAB 2020년대 이후 ETF 유입으로 약화, (2) D25+Q07 CAGR 2.59% 정상구간 기회비용 과대. EXCLUSION: multi-sleeve portfolio 내 defense sleeve(STR_1679 Core+Def, STR_905 3-sleeve 등)는 AX-001에 따라 조건부 성과로 평가, scope 밖. Governor STR_1439(SR 1.532, MDD 19.17%, novelty 10)도 scope 밖.
- 범위: market=KR, family=defense, 
- 근거: L-136, L-140 (L-code 2건)
- 5축 점수: 0.89 (I=0.75 R=1.00 F=1.00 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16

### AX-004 [방법론] [실패]: [방법론 실패 규칙] KR quality_profitability single-signal long-only는 구조적 실패. (1) GP as single-factor(Novy-Marx 2013, Piotroski/Ohlson 결합 없음), (2) Cash-based profitability(Ball 2016) DART 현금흐름 의존 단독, (3) L-134 GSCD 유형 IS-only growth stability composite는 모두 OOS 소멸. EXCLUSION: (a) Quality가 overlay로 작동하는 멀티팩터 블렌드(QMJ+MOM, quality+value 등), (b) 전통 quality composite (Novy-Marx GP + Piotroski F-Score + Ohlson O-Score + Q07 등 복수 quality axis 결합)는 scope 밖 — Scout의 Quality Defensive Composite(A안)은 scope 밖. STR_1679 Q07 defense sleeve는 scope 밖.
- 범위: market=KR, family=quality_profitability, 
- 근거: L-133, L-134, L-139 (L-code 3건)
- 5축 점수: 0.89 (I=0.78 R=1.00 F=1.00 E=0.50 M=1.00)
- 승격: 2026-04-17 | 다음 검토: 2026-07-16
<!-- AXIOM_INJECT_END -->
