# STR_1679v3 Def Sleeve 교체 Mutation 설계 — Scout **FINAL**

**버전**: **revision_final v1.0 (2026-04-17)** — H_1682 VERDICT APPROVE_CONDITIONAL 71 확정 후 공식 승격  
**상태**: **OFFICIAL** (draft 단계 종료)  
**승격 조건 충족**: H_1682 APPROVE_CONDITIONAL 71/100 확정. 1순위 "Q25+R16 cross-family" 확정 가능.

## 배경

Judge Full Audit (2026-04-17) 결과:
- STR_1679v2 Primary Grade A conditional, **ROLE_MISALIGNMENT 공식 확정**
- Def sleeve (Q07+D29) 실질 기여 **0.3pp**만 (avg weight 10.9% × CAGR 2.93%)
- MDD 축소 22.54pp는 전적으로 **Layer 3 overlay (inverse ETF + cash)** 기여
- L-143 Scout 예측 ("Q07+D29 defense drag") 정확성 empirical 확인

**결론**: Def sleeve 5종목이 **사실상 장식**. 교체 필요성 확정.

## 목적

STR_1679v3 = STR_1679v2 구조 + Def sleeve 교체:
- Core 15 (C19 ICIR, 유지)
- **Def 5 (교체 대상)**: Q07+D29 → ?
- Regime weight (95/5 → 80/20 → 60/40, 유지)
- Layer 3 overlay (inverse ETF + cash, 유지)

## Def Sleeve 교체 후보 매트릭스

### 후보 1 (✅ **확정 - 1순위 SELECTED**): Q25+R16 cross-family

**조건 충족 확인**: 
- H_1682 VERDICT = **APPROVE_CONDITIONAL (71/100)** ✅
- S1 실증 SR/MDD gate 통과 여부: H_1682 S1 실행 후 확인 (TODO Forge 전달 완료)
- Q25/R16 Z_Score_Aligned 컬럼 EXIST 확인 (Quant R1 실측)
- Q25-R16 상관 median 0.053 (Quant R1 실측 — cross-family 독립성 입증)

**설계**:
- Def composite = 0.6·z(Q25_Ohlson_O) + 0.4·z(R16_Calmar)
- Top 5 from remaining universe (Core 15 제외)
- AX-003/004/005 전수 PASS
- L-143/L-144 empirical 회피
- stress IC: Q25 +0.659, R16 +2.655 → 양쪽 strong

**예상 효과**:
- Def sleeve 실질 기여: Q07+D29의 0.3pp → **2~5pp** 예상 (R16 stress_pct_pos 1.00 감안)
- Role honesty: 진짜 Defense 기여 확보
- overlay 의존성 감소 가능성 (overlay_dependency_gap 축소)

### 후보 2 (H_1682 FAIL 시): Governor 후보 B (Regime-conditional VRP)

**조건**: H_1682 REJECT/REVISE + 다른 방향 필요

**설계**:
- VRP = VIX² - RV (Variance Risk Premium)
- 한국 KOSPI200 VKOSPI index 활용
- Normal regime: Def 5% (Core momentum 100%)
- Crisis regime (VRP > 90th percentile): Def 40%
- 단점: VKOSPI 역사 짧음 (2003~), STR_1417 기존 시도

### 후보 3 (H_1682 FAIL + Gov B 데이터 부족 시): Active Overlay Framework

**조건**: 위 2개 모두 불가

**설계**:
- Def sleeve 완전 제거 → Core 20종목
- Layer 3 overlay (inverse ETF + cash) 강화
- Barroso & Santa-Clara (2015) factor risk management로 Core weight scaling만
- 단점: Def sleeve 컨셉 포기, factor 다양성 손실

## 구현 Pseudocode (후보 1 기준)

```r
# STR_1679v3: Core C19 (15) + Def Q25+R16 (5) + Regime weight + Overlay
# factor_engine.R 수정

# 1. Load factors
FACTOR_PANEL <- load_month_factors(
  factor_names = c("C19_Composite_Earnings", "Q25_Ohlson_O", "R16_Calmar")
)

# 2. Per month
for (sd in rebal_dates) {
  # Core sleeve (C19 Top 15)
  core <- FACTOR_PANEL[Date == sd & Factor_Name == "C19_Composite_Earnings"]
  setorder(core, -Z_Score_Aligned)
  top_core <- head(core, 15L)
  
  # Def sleeve (Q25+R16 composite, Core 제외 universe)
  q25 <- FACTOR_PANEL[Date == sd & Factor_Name == "Q25_Ohlson_O"]
  r16 <- FACTOR_PANEL[Date == sd & Factor_Name == "R16_Calmar"]
  
  remaining <- setdiff(q25$Ticker, top_core$Ticker)
  def_merged <- merge(
    q25[Ticker %in% remaining, .(Ticker, Z_Q25 = Z_Score_Aligned)],
    r16[Ticker %in% remaining, .(Ticker, Z_R16 = Z_Score_Aligned)],
    by = "Ticker", all = FALSE
  )
  def_merged[, Def_Score := 0.6 * Z_Q25 + 0.4 * Z_R16]
  setorder(def_merged, -Def_Score)
  top_def <- head(def_merged, 5L)
  
  # Combine 20 stocks
  top_20 <- rbind(
    top_core[, .(Date = sd, Ticker, Score = Z_Score_Aligned, sleeve = "core")],
    top_def[, .(Date = sd, Ticker, Score = Def_Score, sleeve = "defense")]
  )
  # ... (regime weight + HRP + overlay 기존 로직 유지)
}
```

## 검증 gate (S5 mutation → S6 Judge)

1. **Core 15 / Def 5 intersection = 0** (L-484 물리 분리 준수)
2. **Def sleeve 실질 기여 ≥ 2pp** (L-143 재현 회피)
3. **overlay_dependency_gap < 0.15** (Role honesty: overlay 의존 감소)
4. **Primary grade ≥ A** (STR_1679v2 77.1 수준 이상 유지)
5. **Base HRP (no overlay) grade ≥ B** (순수 signal 강화 확인)

## Judge L-146/L-147 준수

- **L-146**: overlay-driven MDD improvement은 Core alpha로 계상 금지. STR_1679v3는 Def sleeve 진짜 기여 명시 (0.3pp → 2~5pp 측정 보고).
- **L-147**: 소급 tracker 기록만으로 유효하지 않음. STR_1679v3는 S5 mutation 공식 절차 (Scout 설계 → Forge 구현 → Judge 검증) 준수. 소급 아님.

## 타임라인

1. **H_1682 R2 VERDICT 확정** (대기 중)
2. **VERDICT APPROVE 시**: H_1682 S1 Forge 실행 → S1 Grade 확인
3. **H_1682 S1 PASS 시**: STR_1679v3 설계 확정 + Scout → Forge TODO
4. **H_1682 FAIL 시**: 후보 2/3 선택 후 재설계

## 현재 blocker (Final 버전 2026-04-17 업데이트)

**해소된 항목**:
- ✅ H_1682 R2 VERDICT 확정 (APPROVE_CONDITIONAL 71/100)
- ✅ Scout STR_1679v3 draft → revision_final 승격

**남은 대기**:
- H_1682 Forge S1 실행 (TODO Forge inbox 전달 완료)
- Forge STR_1679v2 재실행 4건 (tail_risk + daily_returns + hurdle split + Core/Def 독립 백테스트)
- H_1682 S1 Hurdle Grade A/B 확정 → STR_1679v3 Forge 구현 activation

## 승격 후 다음 Scout action

1. **H_1682 S1 완료 대기** (Forge)
2. **H_1682 S1 COND_11/12 통과 시** → STR_1679v3 Forge TODO 작성 (이 문서 기반)
3. **STR_1679v3 구현 파라미터** (Forge 전달):
   - `N_CORE=15` (C19 ICIR Top, 유지)
   - `N_DEFENSE=5` (H_1682 Q25+R16 composite Top-5, Core 제외 universe)
   - Def composite = 0.6·z(Q25_Ohlson_O) + 0.4·z(R16_Calmar)
   - Regime weight 95/5 → 80/20 → 60/40 (유지)
   - Layer 3 overlay 유지
4. **H_1682 S1 FAIL 시** → 후보 2 또는 3 재검토

## Scout 최종 상태

- 이 문서: **OFFICIAL revision_final**
- H_1682 s0_record: **v2 (12 conditions 반영)** 업데이트 완료
- TODO_S1_H_1682: **Forge inbox 전달 완료**
- L-145: **AX-005 evidence synthesis 완료**
- Strategic context: **Governor 4-scenario A (STR_1679v2 + H_1682 둘 다 PASS) 경로 활성화**

---

작성: Scout, 2026-04-17  
용도: STR_1679v3 Def sleeve 교체 mutation 공식 설계. H_1682 VERDICT APPROVE_CONDITIONAL 71 후 revision_final.
