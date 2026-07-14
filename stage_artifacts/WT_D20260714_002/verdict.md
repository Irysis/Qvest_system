# R26 (FQ-039) Verdict — PG2 8번째 팩터 add/remove/replace 스크린

**판정: CONFIG_SCOPED_NEGATIVE (book-marginal 자본) + 프론티어 2 open**
book_state 무변경. 결과 = 도훈 결정 재료(실편입 = QEPM 6-agent + 도훈 수동).

## 판정 근거 (authoritative = frozen cap-w 축)
- **base**(frozen score_eff top-25 cap-w, selection-level): canonical PORT_t **5.324**, net-active IR **1.275**(window-matched w=0), n=255, turnover 12.5/yr.
- **추가(ADD) 축**: 7후보 × w{0.15,0.30} = 14 arms. **어떤 것도 paired NW-t ≥ 2.0 미달** (best V14_EBIT_EV w0.30 = **1.87**, ΔIR +0.102, holdout paired 1.76). 합격 기준 = paired≥2.0 ∧ ΔIR≥0.05 동시 → 불충족.
- **제거/교체(Extension B) 축**: recon-proxy(fid_eff 0.914) — 절대 자본판정 아님. IS는 C06_TP_Gap 제거를 flag(paired 2.45)하나 **holdout 붕괴(−0.60)** + recon 아티팩트 가능(C06=analyst TP, vintage-noisy). replace C06→M27 IS 2.63/holdout 1.64(<2.0).

## 세 갈래 요약 (전 그리드 = 산출 parquet, 선택 없이 전수)
| 축 | 최우수 | paired(IS/full/HO) | ΔIR(matched) | 판정 |
|---|---|---|---|---|
| ADD (frozen, 권위) | V14_EBIT_EV w0.30 | 1.51 / 1.87 / 1.76 | +0.10 | 미달(paired<2.0) |
| ADD (frozen) | V07_EV_EBITDA w0.15 | 1.77 / 1.81 / 0.39 | +0.12 | 미달 + OOS 감쇠 |
| REMOVE (recon proxy) | C06_TP_Gap 제거 | 2.45 / 2.43 / **−0.60** | +0.22 | OOS 붕괴 = 과적합/아티팩트 |
| REPLACE (recon proxy) | C06→M27_Analyst_Rev_Mom | 2.63 / 2.96 / 1.64 | +0.22 | proxy + HO<2.0 |

## honest prior 정합
06-24 직교 327팩터 t>2=0 · 07-10 book-marginal 프로브 fleet 생존 0 · WT-H001 내부튜닝 포화 — 본 라운드도 자본기여 후보 부재. 신규 요소 4(R6 deployzone 라벨·ΔIR window-matched·R16 신규팩터·composite z-blend)로 재검했으나 벽 재확인.

## 정보성 발견 (frontier signals, next_probe)
1. **value 축 = book 최유망 미결 노출**: book alpha = Core(4F Consensus) + Defense(Q07 quality/M08 resid-mom/Q25 Ohlson) — **순수 value 부재**. value(EBIT/EV·EV/EBITDA)가 cor −0.05(직교)·ΔIR + ·holdout +로 유일하게 일관 양(+)이나 marginal이 유의수준 미달. → **P2: value를 z-blend 아닌 제3 sleeve로 통합**(전이 벽 재시험).
2. **C06_TP_Gap = 최약 incumbent 슬롯 (recon flag)**: IS 제거 이점이나 holdout 붕괴 + recon-proxy → **P1: frozen-book 재구축(`_recompute` SLEEVE_CORE−C06)로만 settle** 가능. C02_EPS_Chg_1m = 필수 팩터(제거 시 paired −7.09, book 붕괴).

## 방법론 무결성
cap-w authoritative + EW/cap-tier dual-basis · ΔIR window-matched(stored 1.416 미사용, 07-13 트랩 방어) · paired∧ΔIR AND-게이트(ΔIR 단독 허위통과 차단) · IS-only 선택 + holdout 1회(C06 과적합 자체검거) · recon proxy 명시라벨 · pin R26_FQ039_20260714.
