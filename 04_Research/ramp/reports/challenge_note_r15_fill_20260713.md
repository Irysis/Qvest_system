# Self-Adversarial Challenge — RAMP R15 (FQ-028, 충원(fill) 규율 축 chain)

- **as_of_date**: 2026-07-13 · **source_version**: RAMP_R15_v1 · **config_hash**: 7f5855e1dc0ce7e4
- **selection_type**: chain · **n_trials_lineage**: 30 (R14까지 27 + R15 3=L-1/L-2/L-3)
- **산출**: `outputs/ramp/r15_fill_{prereg,gates,paired,conc,oossub,summary}_20260713.*` · 하네스 `02_Infrastructure/ramp/run_ramp_r15_fill.R` · 로그 `.cache/_ramp_r15_20260713.txt`
- **판정 요약**: config-scoped negative (충원 규율 config 한정). 진입(반기 top-K20 level36)·퇴출(F-1 rank-only 분기) 전 arm 고정, fill 규율만 변주. parity: R6 anchor Δ=1.39e-5·**base_F1(level36-fill) cap-w 2.9370 == R14 ctrl_F1 2.937 (Δ=2.4e-5, 3-소수 정확 재현 Δ=0.000)**. best cap-w arm=L-3(consist) 2.890(<base F-1 2.937)·best oos arm=L-3 +0.079(base +0.048). HARD 0/5·max full paired −0.377(<2.0). **종결 아님.**

Opus 4.8 native adversarial reasoning으로 R15 산출을 스스로 적대 검증한다. task 지정 3 챌린지(①②③) + 자가 추가 약점(④~⑦). 각 분류 ACCEPT / PARTIAL / REBUTTAL.

---

## 결과 스냅샷 (cap-w authoritative, weighted_screen_bt 계약)

| arm | fill 규율 | cap-w | oos | oos_ew | post17 SR | paired full vs F-1 | paired IS |
|---|---|---|---|---|---|---|---|
| base_F1 | level36 | **2.937** | +0.048 | 0.651 | +0.035 | — | — |
| L-1 fresh | recent18 | 2.732 | −0.056 | 0.491 | −0.095 | −1.228 | +0.282 |
| L-2 nofill | none | 2.652 | −0.089 | 0.446 | −0.088 | −1.547 | +0.342 |
| L-3 consist | 12m×3 min | 2.890 | **+0.079** | **0.675** | +0.031 | −0.377 | −0.526 |

핵심: **어떤 fill 규율도 level36-fill(챔피언 F-1의 기본값)의 cap-w를 넘지 못한다.** L-3(consist)가 최근접(2.890)이며 oos도 소폭 상회(+0.079)이나 둘 다 천장(cap-w~2.94·oos~+0.12) 안. L-1(fresh)·L-2(no-fill)는 오히려 악화.

---

## 태스크 지정 챌린지

### ① [REBUTTAL] L-2 무-fill이 K 축소 sweep(R6 K10)과 수렴하는가
**측정**: L-2 pool size mean=**19.03**(min 11 max 20), filled=**0**(전 exit-only anchor 미충원), underfill_months=24/37. cap-w=**2.652**. 대조: R6 Ppure_W36_K10 cap-w **1.905**·oos −0.375 / R6 no-exit K20 2.612 / base F-1 2.937.
**판정 REBUTTAL**: L-2는 **K 축소 sweep과 수렴하지 않는다**. 유효 K(pool 평균)가 19.0으로 K20에 근접(min 11은 반기 진입 직전 일시적, 진입서 top-K20 완전 재충전) → K10(=반영구 축소)의 cap-w 1.905와 전혀 다른 지대. **오히려 진단적으로 유의**: L-2 cap-w 2.652 ≈ **R6 no-exit K20 2.612**(Δ+0.04) — 즉 fill을 제거하면 F-1의 exit 이득(2.612→2.937)이 거의 소멸하고 no-exit base 수준으로 회귀한다. → **F-1의 cap-w 우위는 '퇴출 자체'가 아니라 '퇴출 슬롯을 level36-top으로 재충원'하는 데서 나온다**는 직접 증거. 무-fill은 K-collapse가 아니라 'F-1에서 재충원 이득만 제거한 형태'.

### ② [REBUTTAL] L-1 신선-fill이 FM 수렴하는가 (fill-only 적용이어도 pool FM화?)
**측정**: Jaccard(L-1↔FMpure)=**0.442** vs (base↔FMpure)=**0.418** → Δ=**+0.024**(fill-only FM 주입폭). Jaccard(L-1↔base)=**0.938**. fresh_frac=0.778(빈 슬롯의 78%를 level36-fill과 다른 팩터로 충원 — fresh 실작동). 대조: R13 D-1(감쇠속도 *선별 전체*)은 Jaccard vs FM 0.713(FM 수렴 붕괴).
**판정 REBUTTAL**: L-1은 **FM으로 수렴하지 않는다**. fill이 recent18(=팩터 모멘텀 신호)로 다른 팩터를 실제로 뽑지만(fresh_frac 0.78), 개입 대상이 분기당 ~2슬롯뿐이라 pool 정체를 못 바꾼다(L-1↔base 0.938·L-1의 FM 근접도는 base 대비 +0.024만 증가). = R13 D-1의 전면 FM 수렴(0.713)과 대조적 — **fill-only 적용은 FM 오염을 구조적으로 억제**(pool 골격은 level36 진입·F-1 퇴출이 지배). 단 신선-fill은 **cap-w를 악화**(2.937→2.732): 모멘텀-hot이나 level-weak 팩터를 재유입해 composite 희석. 신선함이 유리하다는 가설은 실측 기각.

### ③ [ACCEPT] fill 개입 빈도가 낮아 검정력 한계인가
**측정**: exit-only anchor=37개(교대구조 ExExEx상 반기당 1회 exit-only 점검), rank 퇴출 총 72회, anchor당 배출 slots 평균=1.95. Jaccard(L-2↔base)=0.955·(L-1↔base)=0.938·(L-3↔base)=0.941 — 전 arm이 base와 94~96% 동일 pool.
**판정 ACCEPT**: fill은 **저빈도 개입 다이얼**이다 — held K20 중 분기당 ~2팩터만 재충원 대상이고, 그마저 exit-only anchor(반기당 1회)에서만 작동 → arm 간 pool이 94~96% 겹친다. 따라서 negative 판정은 **'이 저개입 다이얼 안에서 cap-w/oos 개선이 검출되지 않음'**이지 강한 기각이 아니다(검정력 한계 정직 병기). 단 방향은 명확: 검출된 소폭 이동조차 전부 base F-1 이하(cap-w) — 저빈도라도 fill 변주는 개선이 아니라 중립~악화 쪽. (honest_frame 예고대로 검정력 한계 사전 인지·기록.)

---

## 자가 추가 약점

### ④ [PARTIAL] IS-only 승자(L-2)가 full 최악 arm — 선택 규율의 잡음
IS paired-t 승자 = L-2(+0.342)인데 L-2는 full paired **최악**(−1.547·cap-w 2.652). IS 3 arm(+0.28/+0.34/−0.53)이 전부 0 근방 → fill 다이얼은 **IS서 base와 구별 불가**. IS 승자가 full 최악인 역전은 IS paired-t에 신호가 없음을 노출.
**판정 PARTIAL**: chain 규율(IS-only 선택)이 잡음 승자(L-2)를 지목했으나, **최종 판정은 게이트 산출 전체**(best cap-w/oos arm = L-3, not L-2)로 하므로 L-2가 졸업 후보로 오르지 않는다 — 규율이 잡음을 격리. 단 이 역전 자체가 'fill 다이얼 = IS-무신호'의 증거(약점이자 진단). chain의 IS-선택은 여기선 무의미(어느 arm도 유의 아님)이나 절차 무결(OSS 미조회 유지).

### ⑤ [ACCEPT] 최선 arm(L-3)도 base F-1을 못 이긴다
L-3(best cap-w/oos arm) cap-w 2.890 **< base F-1 2.937**, oos +0.079 vs +0.048(Δ+0.030 nominal), full paired **−0.377**(음 — F-1과 유의 차 없음, 하물며 우위 아님).
**판정 ACCEPT**: '최선 fill arm'조차 챔피언 기본값(level36-fill)에 **통계적으로 구별불가-하되-nominal 하회**. **어떤 fill 규율도 F-1 기본값을 개선하지 못한다** = config-scoped negative 강력 지지. L-3의 oos +0.079(>base +0.048)·EW-uni oos 0.675(>base 0.651)·post17 SR 양(+0.031)은 '가장 덜 해롭고 소폭 oos-friendly'한 변주이나 자본 후보 아님(paired 무의미·HARD 0/5).

### ⑥ [ACCEPT] 이것은 '기본값이 최적'을 확증하는 null이다
R14 ④가 fill 민감도(ctrl_D2 2.406↔2.503)를 노출해 측정 가치가 있었으나, 결과는 **챔피언 F-1이 이미 최적 fill(level36)을 쓰고 있었다**는 확증.
**판정 ACCEPT**: 이는 발견이 아니라 **기본값-최적 null**이다(정직 프레이밍). fill 다이얼은 측정할 가치가 있었고(R14 노출), 답은 '현직 기본값이 옳았다'. 과대포장 없음 — L-3를 '개선'으로 부르지 않고 '가장 덜 해로운 대안'으로 라벨. 확립 지식: **F-1 챔피언 = {반기 level36 진입 + F-1 rank 퇴출 + level36 재충원}이 return-derived construction의 최적점**.

### ⑦ [ACCEPT] return-derived substrate 천장 재확인
전 fill arm cap-w 2.65~2.94·oos −0.089~+0.079 — 전부 construction 천장(cap-w~2.94·oos~+0.12) 안. EW-uni oos는 L-3 0.675 高이나 cap-w oos 붕괴(post17 SR ≈0).
**판정 ACCEPT**: 충원 규율(construction 마지막 미탐색 다이얼)은 이 측정 프레임(cap-w×oos, return-derived)서 **천장 안**. 선별(R6~R8)·퇴출(R12~R14)·충원(R15) = construction 3대 축 전부 동일 천장에 수렴. revival_signal = 비-수익 substrate(DART insider backfill 연속) 확보 시 **검증된 F-1 construction(진입·퇴출·level36-fill)을 novel 재료에 이식**. return-derived 위 construction 미세조정은 저EV.

---

## 자기합리화 detect (self-check)
- "소진/dead-end" 어휘 사용 없음 → config-scoped negative + next_probe ≥2 도출(아래).
- 정직 병기: L-3 oos +0.079(>base +0.048)·EW-uni oos 0.675(최고)는 방향성이나 (a)cap-w 2.890<F-1 2.937 (b)full paired −0.377(유의 아님) (c)HARD 0/5. '가장 덜 해로운 대안'으로만 라벨, '개선'으로 승격 안 함.
- null 정직: 결과=기본값(level36-fill) 최적 확증 — 발견 아닌 확증으로 프레이밍(⑥).
- 검정력 한계 정직: fill=저빈도 다이얼(pool 94~96% 겹침)이라 negative는 '저개입 내 무검출'이지 강한 기각 아님(③) — 사전 예고·사후 확인.
- 벽 귀속 정직: cap-tier×cap-w + return-derived construction 천장은 제약(고정 축)이지 실패 원인 아님(AX-000 따름정리·INV-7). fill 다이얼의 한계로 정직 귀속.

## next_probe (≥2 의무)
1. **(revival·주력) 비-수익 substrate × 검증된 construction 이식**: 선별(R6~R8)·퇴출(R12~R14)·충원(R15) construction 3대 축이 return-derived substrate서 동일 천장 수렴 확정 → 검증된 F-1 construction(반기 level36 진입 + rank 퇴출 + level36 재충원, 최적 fill 확정)을 **DART insider 패널(FQ-001/FQ-019 armed 하네스)**에 이식. insider backfill 연속 2013+ 도달 후 1커맨드 실측. 상설 프론티어.
2. **(조건부·진단) L-3 consist-fill의 EW-basis/cap-tier 재분류**: L-3 EW-uni oos 0.675(전 arm 최고·>base F-1 0.651)·post17 SR 양(+0.031) — consist-fill의 EW-real 이득이 D3형(벤치-상대 배포성) 결정재료로 라우팅되는지 FQ-015/FQ-016 계보 escalation 적용. **EW=진단 basis, 자본 게이트(cap-w) 우회 아님**(프레임 명시).
3. **(저EV·구조) fill 개입 빈도 상향**: cadence_exit=2로 진입 사이 exit-only 점검 ≥2회 → fill 개입 슬롯을 분기당 ~2 이상으로 확대(검정력 한계 ③ 완화) × L-3 consist-fill 결합. 단 R14가 이미 cadence2를 저EV(회전↑)로 플래그·construction 천장 확정이라 최후순위(기전 검증 전용).
