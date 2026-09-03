# 다음 세션 인계 — 2026-09-01 (측정 축 전환 후 정지 상태)

## 지금 상태 한 줄

**무인 리서치 루프는 도훈 지시로 정지돼 있다**(`reinforce_auto_config.json::enabled = false`).
축 전환이 끝났고, 재개하면 **첫 새 축 entry** 부터 시작한다.

## 왜 세웠나 — 이번 세션의 핵심 발견

**모든 강화 셀이 3종목 포트폴리오를 재고 있었다. 고정 축은 25다.**

기전 2단:
1. `rf_cell_engine.R` 이 이미 상위 25를 잘라 `FACTORS` 를 내보낸다
   (`PANEL[order(Date,-Score)][, head(.SD, .N_MAX), by=Date]` · 실측 `factors_panel.parquet` 월 정확히 25행)
2. `run_paper_replication` 의 `top_n_long` 이 **그 25개를 다시** 분위로 잘랐다
   (`k = max(2, ceiling(n * 0.10))` → `ceiling(25*0.10) = 3`)

거들던 것: 셀 실행 경로가 `portfolio_spec` 에 **`n =`** 을 넘기는데 러너는 **`spec$n_max` / `spec$n_long`**
을 읽는다 — 격자의 `n_max` 가 **한 번도 전달된 적이 없었다**.

★아무도 못 본 이유: 보고 줄이 `n_max <최대 보유종목수>` 였고 **3 ≤ 25 라 제약을 만족한다**.
축이 전달됐는지는 아무도 안 물었다.

**실측 영향 (같은 스펙, 축만 교체)**: 보유 3종 → **25종** · MDD 70.6% → **56.2%** · PORT_t 0.222 → **−0.054**
(등급 C → F). 낙폭 개선은 진짜이고 알파 소멸도 진짜다 — 둘 다 이전 값이 축 인공물이었다는 뜻이다.

## 원장 상태

- `current_axis = "n_max_25"` · `axis_epochs` 1건(전환 사유·실측 근거 포함)
- **entry 15건 전부 `axis_valid = false`, `measurement_axis = "legacy_double_selection_n3"`**
- **측정 시도 147건은 보존** — 축이 다를 뿐 틀린 값이 아니다(사후 재현·귀속 유지)
- 마지막 entry(`RP_20260901_145755_5376_adapted_rulefast`, 20/25)는 축 전환 + 전이 창으로 **park**
- `rf_open_entry` 가 새 entry 에 `measurement_axis` 를 각인한다 — 신규분이 legacy 로 오분류되지 않는다

★**축이 다른 entry 끼리 등급·PORT_t 를 비교하지 말 것.** B/C 등급 순위가 새 축에서 유지된다고 볼 근거가 없다.

## 재개 방법

```bash
python -c "import io,json;p='06_Registry/reinforce_auto_config.json';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=True;io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
```

다음 tick 이 큐 상단 논문(현재 `cond-mat/0410079` 다음)의 충실구현을 띄우고, 거기서 열리는 entry 가
**첫 새 축 entry** 가 된다. 큐는 `alpha-pending 75`.

## 이번 세션에 바뀐 것 (요약)

| 영역 | 변경 |
|---|---|
| 정지 결함 | 소비 키 정본화(`pid_of`) · 고아 claim 회수를 상태 판정 앞으로 |
| B1 | 격자 고정 → 등록부 소비(`rf_factor_arms.R`) · IC 상관 최소화 사슬 · **계열 라운드로빈 시드 회전** · 깊이 1~5 |
| 엔진 | 기저 가중 `w0 = 0.5` 고정(격자 `fixed_axes` 가 정본, 구 스펙은 등가중 폴백) |
| 격자 | 블록 순서 **B1→B2→B3→B5→B4** · B4 **4축 LOO**(오버레이 포함) · 코드 재번호 |
| 승자 해석 | 격자 조회 → **측정된 spec 파일** 기준(B1·B5 셀은 격자에 없다) |
| 자동등록 | B+ 논문 신호 → 팩터 DB(`engine` 템플릿 · 동결 패널) · 게이트 3종 |
| 팩터 DB | `panel_axis` 판정기 · `compute_technical.R` 12종 신설 · registry 위생 4종 제거(373→369) · 슬라이스 창 1400→**1900일**(M12 영구 0행 수리) · 백필 멱등을 "가용성" 기준으로 |
| 가시성 | 부팅 `Data:` 줄에 배출 격차 표면화 (현재 **14** = 백필 대기분) |
| 검사 | 배터리 **116 통과 / 0 실패** (§27~§31 신설, 전부 양성 대조 포함) |

## 계속 도는 것 (의도적)

`daily_refresh` 는 정지 대상이 아니다. `[6d]` 예산제 백필이 밤마다 **technical 12 + C15 + M12** 의
이력을 채운다(밤당 3~4종, 4일 예상). 새 축 리서치가 쓸 팩터 커버리지이므로 남겨 뒀다.
정지하려면 `QVEST_FDB_NO_BACKFILL=1`.

## 남은 항목 (범위 밖으로 분리한 것)

- `factor_evidence.json` 의 `lifecycle_status` 가 항상 `active` — registry 가 `deprecated` 로 표시한
  C14/C17 도 active 로 보고한다(사이드카 결함). `rf_factor_pool` 은 registry 정본을 읽도록 이미 우회했다.
- `build_factor_evidence.py --if-stale` 이 2026-08-20 이후 안 돈 이유 미확인
- **일간 증분 빌드가 배치 빌드보다 얇다** — 202608·202609 가 324종(직전 347~348), `M07_IndMom` 0행.
  최신 달을 쓰는 전략이 그 팩터를 쓰면 조용히 1~2개월을 잃는다. 원인 미규명.
- B2 가 `rf_pick_weight_arms()` 를 호출하지 않는다(스냅샷 5종 고정). B1 에 깐 배선과 같은 형태.
