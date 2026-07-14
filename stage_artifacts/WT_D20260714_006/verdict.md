# R30 (FQ-045) Verdict — value(V14/V07) 잔여 소비면 실측: EW-상대 배포성(A) + MID-tier 조건부 슬로팅(B)

**부모 체인**: R27(FQ-040) → R28(FQ-041) → R29(FQ-044) → **R30(FQ-045)**. R29 next_probe P1(cap-tier 국소화 소비) 직접 소비.
**base 권위**: clean `0_stored_S7`(production_parity_verified, off0 T-1) — §7b 준수. value=`vz_off0`(R29 T-1 clean). READ-ONLY.
**pin**: R28_current_20260714 (RAWDATA md5 c5242397 확인). **prereg sha256**: bc3d2dfd…

---

## 판정 요약 (2건)

**Branch B — CONFIG-SCOPED POSITIVE (screening AND-게이트, full-period). cap-w 국소화 벽 최초 관통(screening).**
> **B2 (non-mega = MID+OTHER에만 value 틸트)**: cap-w paired **2.378** ≥ 2.0 ∧ ΔIR **0.232** ≥ 0.05 → **AND-게이트 PASS**. R29 unconditional(모든 tier에 value, paired 1.243 **FAIL**) 대비 최초 관통. placebo p=0.000·lag1 2.473·paired-diff oos_v2 2.326 = 실신호·PIT-safe·방향(cap-tier 국소화) 확증. **단 자본 아님**: holdout dIR **−0.022**·paired_HO 1.17·post2017_t 1.73·variant 절대 oos_v2 0.452 = 최근/OOS marginal 감쇠(관통은 IS/pre-2017 견인) → **screening-tier candidate**(forge/graduation 미검증). B1(MID-only) FAIL — OTHER(소형가치)가 견인.

**Branch A — pure-value EW track = band-조건부 신호 확인이나 독립 페이퍼트래킹 3호 부적격(redundant).**
> pure-value EW: oos_v2 **0.659**(band, 0.7 근접)·trailing-stable(2.14/2.13/2.26, KR value 감쇠 서사와 달리 감쇠 미검출)·TO 5.0·break-even >50bps·capacity 36m 19억(도훈 규모 적정). **BUT** 기존 P-pure track과 active-corr **0.50**(basis-mixed proxy) + overlap 19.5% > V02_EP(0.34, D3서 redundancy로 독립 불채택) → value 정보 ~절반 P-pure 중복. **=> 독립 트랙 근거 부족.** Z6 blend EW(EWuni 6.39)는 book+value=~book-duplicate로 standalone 무의미. **value paper-track #3 = 독립 EW 트랙 부적격; 상위 EV 소비형태 = Branch B(book-marginal).**

---

## 1. Branch B — MID-tier 조건부 value 슬로팅 (cap-w authoritative)

base clean 0_stored_S7 cap-w top-25: PORT_t 3.058·IR 0.663·TO 13.7. tier = SIZE 월별 내림차순 MEGA(1-10)/MID(11-30)/OTHER(31+).

| cell | boost tiers | var_pt | paired | IS | **HO** | dIR | dIR_ho | post17 | lag1 | ewuni | AND |
|---|---|---|---|---|---|---|---|---|---|---|---|
| (ref) R29 uncond | ALL | 3.85 | 1.243 | 0.918 | 1.075 | +0.153 | — | 1.03 | 1.53 | 6.39 | FAIL |
| B1_MID_only | MID(11-30) | 3.28 | 1.072 | 0.279 | 1.774 | +0.046 | +0.156 | 0.85 | 0.26 | 4.30 | **FAIL** |
| **B2_MID_OTHER** | **non-mega(11+)** | **4.23** | **2.378** | 2.096 | **1.170** | **+0.232** | **−0.022** | 1.73 | 2.473 | 6.59 | **PASS** |

**기전**: value alpha가 non-mega(특히 OTHER 소형)에 국소(project-captier-alpha-localization). R29는 mega에도 value 적용 → marginal 희석. B2는 **mega=순수 base 순위 유지 + non-mega만 value 틸트** → paired 1.243→2.378. B1(MID만) 실패 = MID(11-30) 명목가중 작아(0.07) 부족; **OTHER 포함이 관통 조건**.

**강건성(B2, 선택후 진단)**: placebo(value 셔플 N=40) null paired max 1.104 ≪ actual 2.378, **p=0.000**(실신호). lag1 2.473(동월 look-ahead 부재 — R29/faith 판별기 통과). paired-diff oos_v2 2.326(anchored splits). **한계**: variant 절대 oos_v2 0.452<0.5·명시 holdout(2024-07+) dIR −0.022 = **최근-2년 marginal flat/negative**(두 지표 상충 아님 — window 상이, recency 감쇠 실재). wMID 0.062 = marginal이 top-25 tail 소가중 교체 증폭(구현성 미검증).

**계층 라벨**: metric_type=weighted_screen(cap-w screening) — **admission 권위 아님**(forge build_bt_result authoritative). graduation HARD 3종(PORT_t 2.95 forge·oos 0.7·calmar 0.64) 미검증. **자본 NO-GO.** prior('cap-w 탈출 불가')와의 관계: B2는 탈출이 아니라 cap-w 안 mega-value 미적용(국소화 존중) — screening 관통은 최초이나 자본 반증 아님.

## 2. Branch A — EW-상대 배포성 실사 (D3 dossier form, due_diligence_arithmetic)

| track | EWuni_t | EW IR | oos_v2 | post17 | TE ann | TO | cap_1d 36m | break-even | overlap/corr(P-pure) |
|---|---|---|---|---|---|---|---|---|---|
| Z6_blend_EW | 6.39 | 1.30 | 0.52 | 2.63 | 9.3% | 12.2 | 23.9억 | >50(~68)bps | 12.5% / 0.19 |
| **pure_value_EW** | 3.75 | 0.74 | **0.659** | 1.39 | 11.2% | **5.0** | 19.0억 | >50(~51)bps | **19.5% / 0.50** |

**판독**: pure-value EW는 **trailing-stable**(2.14/2.13/2.26 — 감쇠 미검출, KR value 24/24 감쇠 서사에 반하는 clean 신호)·cost-robust(oos가 비용과 함께 0.659→0.729 상승, IS 구간 더 깎임 = D3 패턴)·capacity 적정. 그러나 **P-pure와 active-corr 0.50**(basis-mixed proxy) = 독립 정보가치 ~절반 중복(P-pure가 이미 EP류 value 로테이션 소비 — D3 §5). D3 선례(V02_EP 0.34로도 독립 불채택)보다 중복 더 큼 → **독립 페이퍼트래킹 3호 부적격**. Z6 blend는 book-duplicate. **EW-트랙 자체가 실투자 벤치 mandate 부재(프레임 전용 채점, D3 §3 한계).**

## 3. value_quality_spread 리스크 맥락 (정직)
현재 백분위 **0.175**(07-14) — 06-24 '사상최대'(reference-kr-value-factor-decay)에서 크게 압축 = reversion 상당분 기진행. **늦은-사이클 리스크**: clean holdout 양성(2024-26)이 소진된 되돌림의 후행 관측일 가능성 — B2 holdout dIR −0.022·pure-value post17 1.39와 정합 방향. forward value 기대 하향. (스프레드는 리스크 맥락으로만 — 타이밍/활성화 금지 준수: factor-of-factors NULL·regime FALSIFIED·시장타이밍 4중부정.)

## 4. governance / prior 정합
- book_state·05_Production·outputs/ramp 무변경. 02:00 insider crawl + R9 자동발사 무접촉. n_trials_r30=4(chain, sweep 아님 → DSR 게이트 부적용·진단 산출). **value(V14/V07) family 누적 ~8 trial(R26~R30)** — forge 단계 DSR/Harvey 다중검정 엄격 적용 권고.
- honest prior 정합: cap-tier 국소화(alpha=non-mega) 방향 **확증**(B2가 정면 소비). "직교≠수익"·cap-w 국소화 벽은 screening 관통으로 *부분* 완화되었으나 graduation 미검증 — 자본 판정 이전.
- **AX-000**: R29 config-scoped negative를 dead-end로 접지 않고 next_probe P1을 직접 소비 → screening 관통 획득. 탐색 계속.

## 5. next_probe (≥2, 종결 어휘 미사용 — config-scoped positive + 프론티어)
1. **P1 (B2 forge/graduation dossier)**: B2 non-mega slotting score → QEPM forge(build_bt_result authoritative) + judge HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) + holdout falsification(사전등록 구간) + DSR(value family 누적 ~8) + book-marginal ΔIR(recon NAV net-active). governor 정지·도훈 confirm. **FQ 신설 후보(screen-tier→graduation 승격 시도).** 특히 variant 절대 oos 0.452<0.5 정면 관통 여부가 관건.
2. **P2 (tier-cut 민감도 + OTHER 정제)**: B2 견인원=OTHER(31+) → tier 경계(top-10/30) 민감도 + OTHER 내 liq/capacity 필터 강화 시 marginal 생존. wMID 0.062 소가중 증폭 우려 정면 검증. IS-only.
3. **P3 (recency 감쇠 판별 + tripwire)**: holdout dIR −0.022 + spread 압축 0.175 → value marginal 최근-2년 flat이 일시적 vs 스프레드 소진 후행인지 판별. monitoring 월간 trailing-12m paired tripwire 등록 검토. 늦은-사이클 규율.
