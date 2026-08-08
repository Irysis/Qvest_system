# FQ-141 착수 전 사전 확인 — 전제 기각 (2026-08-08, Q-Lead read-only)

**대상**: FQ-141 "★사이즈 중립 composite — EW basis 2.86 을 cap-w 로 옮길 수 있는가"
**원천**: WT_D20260803_007 `next_probe.NP-1` = `layer_bottleneck_map.md` v48 "★★부수 확립 = 다음 라운드 좌표"
**성격**: 실측 아님(read-only 아티팩트 재판독 + 계약 코드 확인). 라운드 미착수.
**판정**: **동기(rationale) 기각 — 라운드는 재설계 대상**. 개입 자체(사이즈 중립 구성)는 여전히 미측정이나, 기대 효과크기의 근거가 사라졌다.

---

## 1. FQ-141 이 서 있던 전제

> "무작위 K=20 composite 의 cap-w PORT_t 평균이 −0.941, EW-유니버스 basis 로는 LEVEL_TOP_K20 이 2.860.
> 즉 **벽의 상당분이 신호가 아니라 사이즈 노출이다**." (WT-007 NP-1 rationale)

이 문장은 두 개를 하나로 묶는다: ①포트폴리오 자신의 사이즈 구성 ②벤치마크의 가중 방식.

## 2. dual-basis 는 벤치마크를 바꾼다 — 포트폴리오가 아니라

`02_Infrastructure/contracts/canonical_screen_bt.R::.canon_diag_ew_universe()` 실코드:

- L97 `pe <- merge(pr[, .(date, ret_net)], ewb[, .(date = Date, ew_bench_ret)], by = "date")`
  → **포트폴리오 수익 `ret_net` 은 cap-w 경로와 동일 객체**. 재구성 없음.
- L103-104 `benchmark_returns_tbl <- data.table(..., benchmark_ret = pe$ew_bench_ret, benchmark_id = "EW_universe_prefilter")`
  → **바뀌는 것은 벤치마크뿐**.
- L117 자체 라벨: "HARD 게이트 **비바인딩** — cap-w basis(bench_dt)가 판정 권위".

∴ `port_t_ew_universe = 2.860` 은 "사이즈 노출을 제거하면 얻을 알파"가 아니라
**같은 포트폴리오를 동일가중 벤치로 채점한 점수**다. capw−EW 격차는 전적으로 **벤치마크 차이**이며,
포트폴리오의 사이즈 노출에 대한 증거가 아니다. NP-1 의 "⇒" 는 범주 오류.

## 3. 교차-arm 실측도 같은 방향 (WT-007 `dual_basis.cap_w_vs_ew`, 투자가능 arm 13)

| 축 | 값 | 읽는 법 |
|---|---|---|
| `cor(gap, cap_share_mega)` | **0.151** | 사이즈 노출이 격차를 **설명하지 못함** |
| `cor(port_t_capw, cap_share_mega)` | **−0.405** | mega 비중 높을수록 cap-w **나쁨** |
| `cor(port_t_capw, mega+mid)` | **−0.451** | 동일 |

선별 **상위** arm 평균 mega **0.0229**(유니버스 base 0.028의 0.82배) → capw 평균 −0.08
선별 **하위** arm 평균 mega **0.0976**(base의 3.49배) → capw 평균 −0.627

즉 **mega 를 많이 담은 쪽이 기각된 arm** 이다. 사이즈 중립화 = mega 비중을 base 쪽으로 올리는 조작이므로,
상위 arm 의 구성을 하위 arm 쪽으로 미는 방향이다. "중립화하면 2.86 이 옮겨온다"는 기대의 근거가 없다.

⚠ 한계(정직): 위 상관은 **교차-arm** 이고 `cap_share_mega` 는 선별의 *결과*라 알파 내용과 교락된다.
특정 arm 을 사이즈 중립화하는 **arm-내 개입**의 효과를 직접 반증하지는 않는다 — 그것이 원래 FQ-141 이
재려던 것이고, 여전히 미측정이다. 이 사전 확인이 기각한 것은 **개입이 아니라 기대 효과크기의 근거**다.

## 4. 기존 `SS_` arm 은 사이즈 중립이 아니다

`arms[].kind` 실측: `SS_A_REL_TOP` / `SS_A_REL_BOT` / `SS_SINGLE_BEST` = **`single_split`**, `n_months = 96`
= 시간 분할 arm. 사이즈 층화 arm 은 이 라운드에 **없다**. FQ-141 개입은 진짜 미측정이 맞다.

## 5. 방향 주의 — 벤치는 고정 축이다

Production Constraints 의 benchmark(KOSPI200 total return, cap-weighted)와 cap-w HARD 판정 권위는
**문제의 고정 축**이다(AX-000 따름정리 · axiom-engine INV-7). "EW basis 로는 2.86" 을 성취로 승격하거나
판정 basis 를 EW 로 옮기는 서술은 **게임을 바꾸는 쪽**이므로 금지. CLAUDE.md 가 dual-basis 를 도입한
취지도 정반대 — "post-2017 감쇠의 상당부분 = **mega-cap 벤치 아티팩트**" 라는 **기각 전 확인 의무**이지
승격 경로가 아니다.

---

## next_probe (≥2, answer-principles 3호)

- **NP-A (저비용·선행)** — capw−EW 격차의 **벤치-측 분해**: 동일 167개월 창에서 cap-w 유니버스 벤치와
  EW 유니버스 벤치의 실현 수익차를 직접 산출. 격차가 arm 무관 상수에 가까우면(투자가능 13 arm gap
  범위 −0.26~−2.27, POOL_EW −0.446 포함) 벽은 포트폴리오 구성이 아니라 **벤치 레짐**이며, 어떤
  포트폴리오-측 개입으로도 회수 불가임이 확정된다. 이걸 먼저 재지 않으면 FQ-141 은 회수 불가능한
  양을 쫓는 라운드가 된다.
- **NP-B (FQ-141 재설계본)** — 개입을 "사이즈 중립"이 아니라 **"cap-w 벤치를 실제로 이긴 이름을 담는가"**로
  재정의. cap-tier 정원 배분이 아니라, cap-w 벤치 수익 기여 상위 종목에 대한 선별기의 적중률(hit rate)을
  재는 것이 직접 질문. §3 이 시사하는 바 = 현 선별기는 그 이름들을 **못 고른다**(mega 0.82× base).
- **NP-C (파급 점검)** — `layer_bottleneck_map.md` v48 이 이 범주 오류를 "다음 라운드 좌표"로 등재했고,
  이 지도가 **자율 라운드 선택의 근거**다(answer-principles 5호). 같은 conflation 이 다른 행에도
  있는지 dual-basis 인용 지점 전수 확인.

## 부활 조건 (INV-7)

FQ-141 원안은 NP-A 가 "격차의 상당분이 arm-의존(벤치 상수 아님)"으로 나올 때 부활. 그 경우에만
포트폴리오-측 개입이 회수할 여지가 실재한다.
