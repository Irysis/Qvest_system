# Composition Search 자율 프로그램 (도훈 mandate 2026-06-11)

**목적**: PG2급 조합(= sleeve 1~3 × 배분 × overlay 스택 × cash 정책)을 자율 탐색. 06-02 자율 프로그램의 탐색 단위 상향(알파 부품 → 조합 완성차). 1차 목표 = book SR 2.0(백테)·CAGR16·MDD<25 갱신/대체. SR 2.5는 제약완화 전제 stretch.

## 탐색 문법
```
조합 = [sleeve 1~3: family-깊은 composite, 직교 cor<0.3]
     × [sleeve 배분: Σnames≤25, long-only, w∈[0,0.20], Σw=1]
     × [overlay 스택: 국면탐지기(M4/AR/분포예측) × exposure 정책(boolean/연속)]
     × [cash 정책]
```

## 사전 제외 (반증 영역 — 재탐색 금지)
- 이질 팩터 가산 Z 평균/가중 composite (breadth 스윕 + winsorize 아티팩트 이중 반증, 2026-06-11)
- 동질 풀(cor 0.73~0.80) × 국면-IR 조건화 모듈 로테이션 (4중 실측 기각)
- composite 위 가중축 변주 (HRP/RMT/copula/CVaR/NCO/MaxDiv/minvar 전부 EW 이하)
- standalone 단일팩터 top-N 스크린 (327 전수 + AX-007)
- pre-winsorize anchor 인용 (전면 무효)

## 3-Track
- **Track S (sleeve 생산)**: 살아있는 신호만 — FLOW family(E6 fair-trial), revision Core 전종목 재구성, Q07 defense 재조합. 산출 = register_module.
- **Track C (조합 탐색)**: 모듈 풀 부분집합 × 배분 grid 사전등록 sweep, run_wf_ensemble 실측.
- **Track O (overlay 실험실)**: B3 combine 재설계(M4×AR 곱 처리), 분포예측 연속 exposure. book base 위 A/B.

## 거버넌스 (기존 헌법 그대로)
- 조합 탐색 = **명시적 sweep**: selection_type="sweep", 후보 사전등록, DSR≥0.5 HARD, n_trials 전량 계상
- 측정 사다리: screening(canonical) → essence_score(backtested) → book-marginal ΔIR≥0.05 + cor<0.3 → forge-authoritative → judge → **governor admit = 도훈 수동**
- 실측-only(measurement-graduation), PIT C1~C15, 비용 v2.4_kr_retail_15bps
- cycle 종료 시 텔레그램 brief + L-code/FMT 기록

## Cycle 1 (2026-06-11 착수)
- Track O: B3 overlay combine 재설계 — B2 진단(M4↔AR 91% 중복, 중간밴드 과방어 +1.4%/월) 기반 combine 후보 사전등록 → realized 경로 A/B
- Track S: FLOW family fair-trial Stage A — 데이터 인벤토리 → 6~10 spec 사전등록 → screen 게이트(PORT_t≥1.96 ∧ 2017+ >0)
