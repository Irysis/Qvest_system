# R26 (FQ-039) Self-Adversarial Challenge Note

**규약**: v8.2 Self-Adversarial (Opus 4.8 자체 적대검증, finalize 직전). AX-008 3-source 중 1개. No Silent Override (Charter §8).
**분류 규칙**: ACCEPT(위반 수정) / PARTIAL(부분 인정+보완) / REBUTTAL(학술+L-code+정량 3축 근거).

## 자기 비평 (devil's advocate) — 원 지시 3건 + Extension B 3건

### C1 — Stage 1 스크린이 이미 association 소비 (shortlist 규칙 사전동결로 방어했는가)
**concern**: shortlist 선택 자체가 성과-보고 팩터를 고르는 행위 → association 이중소비.
**분류: PARTIAL.**
- 방어 근거: shortlist 규칙(tier_survival ∩ |cor|<0.5 ∩ IS-PORT_t 상위5)을 **측정 前 사전등록 + sha256 동결**(`f34e8ff9…`). |cor|<0.5 필터는 선택적이지 않음(97/97 전량 통과, max 0.48) — 성과-max 셀렉터 아님. tier_survival은 mechanism 필터(성과 아님). 유일한 성과 셀렉터 = IS deployzone PORT_t 순위, **IS-only**.
- 잔여 인정: 규칙 설계 시 deployzone 특성을 인지한 상태 → 완전 무지 아님. **보완**: 97팩터 전수표(`stage1_deployzone_screen.parquet`) + 5 shortlist 전 blend 결과를 선택 없이 전수 보고. DSR n_trials에 Stage1 자유도 명기(아래 C-DSR).

### C2 — window-matched control 아티팩트 재발 (07-13 deltair_diag 교훈)
**concern**: ΔIR이 stored 1.416 대비면 창-불일치로 +0.067 허위통과(07-13 실증).
**분류: ACCEPT (control 정확 적용).**
- 모든 ΔIR = `IR(variant active) − IR(base active)` **동일 하네스·동일 창**(base를 variant의 정확한 월집합에서 재계산). stored 1.416/canonical 1.327은 **일절 미사용**(basis 라벨만 기록).
- ★재발 방지 핵심: ΔIR 단독이면 value add가 +0.08~0.12로 0.05 문턱을 "통과"하나 — **paired NW-t를 동시 요구**(best 1.87<2.0)하여 허위통과 차단. ΔIR과 paired를 AND로 묶은 것이 정확히 07-13 트랩의 방어. (ΔIR>0.05 ∧ paired<2.0 = "IR 개선처럼 보이나 통계적으로 노이즈와 구분 불가" — 정직 보고.)

### C3 — blend가 기존 7팩터 정보의 재포장인가 (cor 분해)
**분류: value=REBUTTAL / M27=PARTIAL.**
- REBUTTAL(value): shortlist value(V14 EBIT/EV·V07 EV/EBITDA·V02 EP)의 deployzone active vs book active cor = **−0.04~−0.07**(거의 직교). 그리고 book alpha 구성 = Core(4F Consensus: SUE/EPS-chg/ESBR/TP-gap) + Defense(Q07 quality·M08 resid-mom·Q25 Ohlson) — **순수 value 축 부재**. → value는 재포장 아닌 신규 노출. 학술: Fama-French 1993 HML·Asness-Frazzini 2013 value-quality 직교. 정량 3축: cor(−0.05)·ΔIR(+0.10 양수)·holdout(V14 +1.76 양수). 
- PARTIAL(M27_Analyst_Rev_Mom): cor 0.29(중간)·Consensus core와 축 중첩(analyst-revision ≈ SUE/EPS-chg family). → 부분 재포장 위험 인정, ADD paired 음수(−0.65)로 실측 열위 확인.

### C4 (Ext-B) — LOO 슬롯 선택이 IS 정보 소비
**분류: ACCEPT (IS-only + OOS가 자체 검거).**
- 슬롯 선택 = IS paired 최대(C06_TP_Gap) — IS-only(measurement-graduation §3 chain ②). holdout은 최종 1회.
- ★자기검거: C06 제거의 IS 이점(paired 2.45)이 **holdout에서 붕괴(−0.60)** → IS 슬롯선택이 과적합-취약임을 OOS가 직접 falsify. 따라서 C06 pruning을 **finding으로 광고하지 않음** — frontier 가설(frozen 검증 필요)로만 강등. 이것이 IS-only+holdout 규율이 작동한 증거.

### C5 (Ext-B) — C06 제거 이점이 재구성(recon) 아티팩트인가
**분류: ACCEPT (핵심 caveat).**
- recon fid_eff median 0.914이나 **C06_TP_Gap = analyst target price = vintage drift 최대**(재무 consensus 재추정) → C06의 recon z가 가장 noisy → 그 noise 제거가 recon book을 개선하는 것이 **frozen book의 C06 기여와 무관**할 수 있음. 
- 결론: recon으로 "frozen book에서 C06가 나쁘다"를 판정 **불가**. Extension B의 remove/replace는 전부 recon-proxy → **절대 자본판정 아님**(frozen ADD 축만 authoritative). C06 pruning = next_probe(frozen 재구축 `_recompute` SLEEVE_CORE−C06 필요)로만 이관. holdout OOS 붕괴(C4)와 합쳐 이중 강등.

### C6 — self-rationalization auto-scan
"미미/관행/실무적/보수적이면 OK/대부분 동일" 사용 여부 grep → **미사용**. 모든 negative를 수치로 보고(paired 1.87·2.45·−0.60 등). 회피표현 0.

## Self-Adversarial 종합
- HIGH severity 위반: 0 (PIT·hard-constraint·AX axiom hard FAIL 없음).
- 방법론 무결성: cap-w authoritative + window-matched control 정확 + IS-only 선택 + holdout 자체검거 + recon proxy 명시라벨.
- Q-Lead escalate trigger: 미발동(HIGH≥5 / AX hard≥3 / C1 lockbox 위반 없음).
- verdict 방향: CONFIG_SCOPED_NEGATIVE(book-marginal 자본) + frontier 2 — 적대검증이 오히려 negative를 강화(C4/C5가 Ext-B 양성 IS를 강등).

## AX-008 Triangulation
- self-adversarial: PASS (본 note).
- 측정 무결성(forge-equivalent): canonical/weighted_screen_bt contract 경유 실측 = build_benchmark_compare 동일 함수. PASS.
- 2/3 충족.
