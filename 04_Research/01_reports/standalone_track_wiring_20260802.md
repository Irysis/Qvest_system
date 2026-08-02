# screen_route 소비 배관 수리 — STANDALONE_TRACK 소비자 0 결함

**일자** 2026-08-02 · **발단** WT-D20260802_005 실측 적발 · **대상** `02_Infrastructure/hurdle_gate.R:1581-1599` screening tier 라벨
**작업 트리** `claude/nice-bose-ef7044` (worktree `.claude/worktrees/nice-bose-ef7044`), 커밋 `44b1defa` + main 병합 `f5a651d9`.
**병합 상태** 브랜치가 main(20:06 시점)을 전부 포함하므로 **fast-forward 병합 가능**. 병합 전까지 main 부팅에는 상태라인이 뜨지 않는다.
```bash
git -C C:/Users/99922/OneDrive/Quant_Module_Moltbot merge --ff-only claude/nice-bose-ef7044
```
**측정 기준** 스캔은 main 저장소 실데이터(`stage_artifacts/alpha_search` 715 run-dir) 기준. 워크트리 자체 데이터로 재실행해도 동일 수치(50/50/20/5)임을 대조 확인.

---

## 1. 결론 요약

| 항목 | 결과 |
|---|---|
| STANDALONE_TRACK 라벨 발급분 | **50건** (manifest 47 + hurdle_result-only 3) |
| 그중 standalone 판정을 받은 건 | **0건** — 3주~7주 전량 미처분 |
| 소비자 0인 route (census 결과) | **STANDALONE_TRACK · FR_RCMA · TURNOVER_REVIEW** 3종 (STANDALONE_TRACK 외에도 2종 더 있었음) |
| 미처분 50건 중 graduation HARD 3종 통과 | **0건** (PORT_t≥2.95: 0 / oos≥0.7: 0 / calmar≥0.64: 0) |
| 부수 발견 — catalog∩quarantine 중복 잔존행 | 5건 (Chen-Welch 포함) |

**한 줄**: 라벨은 발급됐고 후보는 원장에 있었지만, "이 후보가 standalone 졸업 심사를 받아야 하나"를 **묻는 코드가 없었다**. 배관을 놓았고, 그 배관이 죽으면 죽었다고 말하도록 위반 주입으로 검증했다. 다만 회수된 50건 중 현재 저장 실측치로 자본 게이트를 통과하는 건 없다.

---

## 2. 유실 기전 — 최초 진단의 정정

착수 시 전제는 "Chen-Welch 가 quarantine 에 유실됐다"였다. **실측 결과 이 전제는 부정확하다.**

`STR_AS_20260709_074129_30048` 의 실제 원장 상태:

| 원장 | grade | fr_eligible | metric_type | registered_at |
|---|---|---|---|---|
| `module_catalog.json` | B (essence) | **TRUE** | backtested | 2026-07-09T07:46:48 |
| `module_quarantine.json` | A (proxy) | FALSE | proxy | 2026-07-09T07:45:46 |

즉 후보는 **정상적으로 catalog 에 FR_ELIGIBLE 로 등재돼 있었다**. quarantine 행은 `run_alpha_search.R:297` 의 재측정-전 중간 기록이 62초 뒤 catalog 등재(`:374`) 후에도 지워지지 않고 남은 것 — "quarantine 에 유실"처럼 보인 겉모습의 실체다.

**진짜 기전**은 그보다 한 층 위에 있다:

```
hurdle_gate 라벨 발급 → module_catalog 등재 → build_module_performance.R → factor-rotation FR 풀
                                            ↑
                                  여기서 끝난다. standalone 졸업 심사로 가는 분기가 없다.
```

`module_catalog.json` 의 소비자는 factor-rotation FR 풀 빌더뿐이다. 생산자 주석(`hurdle_gate.R:1584`)은 STANDALONE_TRACK 을 `# 기존 등급 경로가 이미 소화` 라고 적었지만, **그 "등급 경로"가 실제로 도달하는 종점은 FR 풀이다.** 라벨과 판정 사이에 원장이 없었다.

> 이 결함의 계통: 이 저장소가 반복해 밟은 **"존재 검사로 정체성 검사를 대체"** 의 변종이다. 후보가 *원장에 있음*(존재)이 *심사를 받았음*(처분)으로 읽혔다.

---

## 3. Census — route 값별 소비자 실존 (작업 1)

`hurdle_gate.R:1581-1599` 발급 route 전량과 소비자 코드 대조. 산출물(`stage_artifacts/`, `qepm/research/results/`) 은 데이터이므로 소비자 판정에서 제외.

| route | 발급 실적 | 전용 소비자 | 판정 |
|---|---|---|---|
| `NONE` | 383 | — | 무발급 라우트, 소비 대상 아님 (정상) |
| `OVERLAY_CANDIDATE` | 20 (전부 `\|FR_RCMA` 결합) | `02_Infrastructure/regime/overlay_candidate_queue.R:36-37,70-71` | **유일하게 완결돼 있던 경로** |
| `STANDALONE_TRACK` | **50** | **0** | 본 작업으로 신설 |
| `FR_RCMA` | 20 (단독 발급 0) | **0** | factor-rotation 측 판독 코드 없음 |
| `TURNOVER_REVIEW` | **0** | **0** | 설계상 기록 전용(`hurdle_gate.R:1590` 주석). 아직 발급된 적 없음 |
| `DPL_FEATURE` | 0 (구 manifest 1건 잔존) | 0 | v8.3 발급 중단 |

**보조 발견 — 유일한 범용 reader 의 무판별성**: `run_alpha_search.R:326-327` 이 `OVERLAY_CANDIDATE|FR_RCMA|DPL_FEATURE|TURNOVER_REVIEW` 를 **하나의 정규식 OR** 로 읽어 재측정을 트리거한다. 어느 값이 맞든 동일 동작이므로 route 별 판별력이 0이고, `STANDALONE_TRACK` 은 이 정규식에서 아예 제외돼 있다.

**FR_RCMA 배관이 끊긴 정확한 지점**: FR_RCMA → RCMA 로 갈 유일한 물리 경로는 `register_module()` → `module_catalog.meta` → 소비자였으나, `register_module()` 은 screen_route 를 **받지도 쓰지도 않는다**(호출자 12곳 전부 meta 에 넣지 않음). 실측: `module_catalog.json`(523KB)·`module_quarantine.json` 내 `screen_route` 문자열 **0회**. 그 결과 `overlay_candidate_queue.R:70` 의 `mod$meta$screen_route` 분기는 영구 빈 분기다(해당 파일 `:13` 주석이 "현재 0건, 배관 선설치"로 자인).

---

## 4. 배선 (작업 2)

### 신설 — `02_Infrastructure/portfolio/standalone_track_queue.R`

기존 `overlay_candidate_queue.R` 선례를 그대로 따르되, 그 선례가 갖지 못한 **양방향 정합**과 **0-이 아님 보장**을 추가했다.

- **수집**: `strategy_manifest.json`(정본) + `hurdle_result.json`(manifest 결손 런 보강 — 이걸 안 보면 3건이 사각에 남는다)
- **처분 대조**: `06_Registry/standalone_track_dispositions.json`(신설) ∨ `alpha_frontier_queue.json` 언급 ∨ `live_track/` 등재. 셋 다 없으면 `disposition="none"` = backlog
- **출력**: `06_Registry/standalone_track_queue.json` (PORT_t 내림차순 = dossier 우선순위)
- **CLI**: `Rscript 02_Infrastructure/portfolio/standalone_track_queue.R [--json] [--no-write] [--status-line]`

핵심 설계 4가지:

1. **FR 풀 등재는 처분이 아니다.** `fr_eligible=TRUE` 여도 미처분으로 남는다. 이것이 Chen-Welch 재발 경로를 막는 지점이고, 검사기가 별도 항목으로 잰다(`fr_pool_is_not_disposition`).
2. **route_consumer_map 을 코드에 명시**하고, 검사기가 생산자 파일을 실독해 대조한다. 새 route 를 발급하면서 소비자를 안 만들면 배터리가 즉시 FAIL 한다 — 이번과 같은 결함이 다음 라벨에서 반복되지 않게 하는 장치.
3. **양방향**: 발급→원장 누락뿐 아니라 원장→발급 역추적 불가(`orphan_ledger`)도 잰다. 단방향만 보면 원장이 유령 행으로 오염돼도 초록이 뜬다.
4. **0 은 합격이 아니다.** 스캔 소스 부재·소비 원장 부재·라벨 0건은 전부 `stop()`(UNREPORTED). 상태라인도 깨진 루트에서 초록 줄 대신 `UNREPORTED` 를 낸다.

### 부팅 노출 — `bootstrap.sh` §8j

```
StandaloneTrk: 미처분 50 / STANDALONE_TRACK 발급 50 · 최상위 STR_AS_20260709_074129_30048(PORT_t 2.584) · 소비자없는 route 20 · quarantine 잔존행 5
```

`--status-line`(읽기 전용)로 호출한다. 매 부팅 write 하면 `generated_at` 만 바뀌어 auto-commit 밸브에 잡음을 만들기 때문에, 상태 노출과 원장 갱신을 분리했다.

### `alpha_frontier_queue.json` 을 쓰지 않은 이유

과제가 허용한 두 안(FQ 자동 등재 / 전용 대기 원장) 중 **전용 원장**을 택했다. 근거: (a) FQ 는 110항목 규모의 도훈-소유 SOT 이고 `dohoon_decision` 항목을 포함하는데 50행을 자동 주입하면 owner 표기 규약이 무너진다, (b) main 의 FQ 는 오늘 다른 세션이 이미 수정한 상태(dirty)라 워크트리의 구 사본을 편집하면 병합 충돌이 난다. 상시 노출 책임은 부팅 상태라인이 진다.

---

## 5. 전수 재스캔 (작업 3)

**미처분 50건 = STANDALONE_TRACK 발급 전량.** 처분 이력이 있는 건 하나도 없었다.

proxy grade 분포 A 5 / B 45, essence grade 분포 B 3 / C 39 / F 7 / 미측정 1.

### graduation HARD 3종 대조 (저장 essence 기준)

| 게이트 | 문턱 | 통과 |
|---|---|---|
| `portfolio_alpha_t_nw_lag3` | ≥ 2.95 | **0 / 49** |
| `oos_retention` | ≥ 0.70 | **0 / 49** (49건 전부 < 0.50 = 무조건 FAIL 밴드) |
| `calmar` | ≥ 0.64 | **0 / 49** |

### PORT_t 상위 5 (dossier 우선순위)

| strategy_id | PORT_t | oos | calmar | proxy/ess | 전략 |
|---|---|---|---|---|---|
| `STR_AS_20260709_074129_30048` | 2.584 | −0.052 | 0.346 | A/B | Chen-Welch 2026 RD-to-Market Survivor |
| `STR_AS_20260612_154914_1055315` | 2.523 | −0.191 | 0.362 | A/B | Balanced multi-factor base signal |
| `STR_AS_20260612_161342_1312338` | 2.353 | −0.128 | 0.313 | B/B | SUE + EPS revision base signal |
| `STR_AS_20260612_143809_686286` | 2.229 | 0.082 | 0.308 | B/F | Earnings Revision Breadth |
| `STR_AS_20260612_132740_321995` | 2.215 | −0.400 | 0.318 | B/F | Piotroski F-Score |

**정직 고지 — 이 표를 기각 판정으로 읽지 말 것.** 위 수치는 라벨 발급 시점(2026-06~07)에 `module_catalog.meta.authoritative_essence` 에 저장된 **cap-w basis** 값이다. 세 가지 유보가 붙는다:

1. **dual-basis 의무 미이행분** (v8.3, measurement-graduation §6): cap-w HARD 판정은 불변이나 **기각 전 EW-유니버스 대비·cap-tier 분해 확인이 의무**다. WT-005 가 Chen-Welch 를 canonical 재실측했을 때 cap-w 2.537 / **EW-uni 3.610** 로 basis 간 격차가 컸다 — 저장 cap-w 값만으로 기각하면 v8.3 규약 위반이다.
2. **oos_retention 통계량 버전 미확인**: §3 의 v2 정본은 anchored 3분할 {55/65/75} 중앙값인데, 저장값이 v1 단일절단인지 v2인지 라벨에 없다. 49건 전량이 음수인 것은 v1 단일절단 특유의 불안정성을 시사한다(같은 시계열에서 splits 0.55/0.59/0.78 이 나온 실측 선례가 있다).
3. **vintage**: 07-02 벤치 IKS001→IKS200 수리 이전/이후가 섞여 있을 수 있다. 06-12~06-13 라벨분(45건)은 재베이스 대상 시점이다.

따라서 이 50건의 정본 처분은 "기각"이 아니라 **"저장 cap-w 기준 HARD 미달 — dual-basis 재실측 후 확정"** 이다. 처분 기록은 `standalone_track_dispositions.json` 에 남긴다(현재 비어 있음 = 아직 아무 판정도 안 했다는 정직한 상태).

### 부수 결함 — catalog∩quarantine 중복 5건

| strategy_id | catalog | quarantine |
|---|---|---|
| `STR_AS_20260613_094148_265194` | C / fr=TRUE | B / fr=FALSE |
| `STR_AS_20260613_094806_265984` | F / fr=TRUE | B / fr=FALSE |
| `STR_AS_20260613_095431_266551` | F / fr=TRUE | B / fr=FALSE |
| `STR_AS_20260621_082546_2116` | F / fr=TRUE | B / fr=FALSE |
| `STR_AS_20260709_074129_30048` | B / fr=TRUE | A / fr=FALSE |

전부 `run_alpha_search.R` 의 6c(재측정 전 proxy 기록) → 6e(재측정 후 catalog 등재) 사이에서 6c 행이 지워지지 않은 것. **quarantine 만 읽으면 최종상태를 정반대로 읽는다** (Chen-Welch: quarantine 은 "grade A · fr_eligible=FALSE" = 기각처럼 보이지만 실제 최종은 catalog "essence B · FR_ELIGIBLE"). 큐가 `shadow_quarantine` 으로 상시 계상한다. `register_module()` 이 catalog 승격 시 quarantine 행을 회수하도록 고치는 것이 근원 수리이나, 이는 본 과제 범위(라벨 소비 배관) 밖이라 별도 태스크로 분리했다.

---

## 6. 위반 주입 테스트 (작업 4)

`08_Tests/portfolio/test_standalone_track_queue.R` — 합성 픽스처, **17/17 PASS**. `08_Tests/hooks/run_all_hooks.sh` SUITES 등재 완료.

배관을 놓는 것만으로는 재발이 안 막힌다. 배관이 조용히 죽으면 미처분 건수가 0으로 떨어지고 그 0이 "밀린 후보 없음"으로 읽힌다 — 이 저장소가 반복해 밟은 결함이다. 그래서 잰 것은 "몇 건이냐"가 아니라 **일부러 넣은 위반이 실제로 발화하는가** 와 **깨끗한 입력에서 오발화하지 않는가** 양쪽이다.

**위반 주입 (8)**: 라벨 발급 + 처분 미기록 / FR 풀 등재가 처분으로 흡수되지 않음 / FR_RCMA 단독 발급 / **미지의 신규 route** / catalog+quarantine 중복 / 역방향 원장 고아행 / 라벨 0건 → stop / 소비 원장 부재 → stop
**오발화 확인 (6)**: 처분 기록분 제외 / FQ 언급 인정 / 토큰 경계(유사 id 오매칭 없음) / screening tier 도입 이전 등록분 미계상 / NONE 라벨만 있을 때 무발화 / 깨진 루트에서 UNREPORTED
**계약 (3)**: 큐 필수 필드 / manifest 결손 런의 id 해석 / route_consumer_map ↔ 생산자 실독 대조

**돌연변이로 검출력 실증**: `ST_ROUTE_CONSUMERS` 에서 `STANDALONE_TRACK` 항목을 제거하자 `route_map_covers_producer` 가 정확히 `미등록 route: STANDALONE_TRACK` 으로 FAIL(16/17) → 원복 후 17/17 회복. 이 검사가 살아 있음을 실측으로 확인했다.

### 검사기가 개발 중 잡아낸 실제 결함 5건

이 검사기는 사후 장식이 아니라 작성 중 결함을 5건 잡았다:

1. **main-guard suffix 충돌** — `grepl("standalone_track_queue\\.R$", ...)` 가 `test_standalone_track_queue.R` 에도 매칭돼, 검사기가 SUT 를 `source()` 하는 순간 CLI 가 덩달아 실행됐다. → `basename()` 정확일치로 교체.
2. **Windows 경로를 정규식으로 사용** — `sub(paste0("^", root, "/?"), "", f)` 가 백슬래시를 역참조로 해석해 통째로 죽었다(`Invalid back reference`). → 문자열 접두 제거 헬퍼 `.st_rel()` 로 교체. r-portability 계통의 신종.
3. **역방향 검사 오검출 78건** — screening tier 도입(2026-06-10) *이전* 등록 모듈을 "라벨 누락"으로 세고 있었다. 78건 상시 점등은 검사기가 무시당하는 지름길이다. → 등록일 + run_dir 실존으로 대상 한정, 78 → 0.
4. **전략 이름을 id 로 사용** — manifest 없는 런에서 `hurdle_result.strategy`(= 전략 *이름*, 예 "52-Week High Anchor Momentum")를 id 로 써서 원장 대조가 전건 실패했다. → `STR_AS_<run_dir>` 파생 id 우선. 이 수리로 `STR_AS_20260612_132740_321995` 가 PORT_t 2.215 실측치와 결합됐다(그전엔 미실측으로 보였다).

5. **배터리 집계 누락** — SUITES 등재만 하고 마지막 줄 JSON 요약을 안 냈다. `run_all_hooks.sh:298-311` 의 `_last_summary_json()` 은 `{"test":...}` 형태의 마지막 JSON 줄만 파싱하고, 없으면 그 suite 를 통째로 **+1 FAIL** 로 계상한다. 즉 17/17 로 통과하는 검사기가 배터리에서는 실패로 잡히거나(운이 나쁘면) 조용히 빠질 자리였다. → 규약대로 JSON 요약 줄 추가, 러너와 동일 경로로 파싱 검증(`pass=17 fail=0 total=17`).

3·4번은 **내가 만든 검사기가 내가 만든 배관의 오측정을 잡은 것**이다. 특히 3번은 "0건 = 정상"의 반대편 함정(상시 점등 → 무시)이고, 4번은 대조 실패가 backlog 를 부풀리는 형태였다.

5번은 이 과제의 결함과 **같은 계통의 자기 재현**이다: 등재(존재)를 소비(집계)로 착각했다. 배관을 놓는 작업을 하면서 그 배관의 하류 연결을 확인하지 않을 뻔했다 — 등재 목록에 이름이 오른 것과 그 결과가 실제로 읽히는 것은 다르다.

**1번 결함의 부작용 — main 에 의도치 않은 쓰기 1건 (정직 고지)**: main-guard suffix 충돌 때문에 검사기를 처음 돌렸을 때 CLI 가 인자 없이 실행됐고(`write=TRUE`), 루트가 `QM_ROOT`=main 으로 해석돼 `06_Registry/standalone_track_queue.json` 이 **main 작업트리에 생성**됐다(14:10). main 의 auto-commit 이 이를 `9aa1b7df` 로 커밋했다. 내용은 현재 판과 counts 동일(492/70/50/50/20/5/0)이라 오염은 아니고, main 병합 시 재생성본으로 해소된다(add/add 충돌을 코드 재실행으로 정본화 완료). 다만 **워크트리 세션이 main 을 건드릴 수 있는 경로가 실재한다**는 사례로 기록해 둔다 — 루트 해석기가 `CLAUDE_PROJECT_DIR` 미설정 시 `QM_ROOT`(=main)로 떨어지는 구조 때문이다.

---

## 7. 남은 것

라운드 종료 계약은 `close_round()` 로 발행했다(`.cache/last_round_closure.json`, verdict_type=`config_scoped_negative`, next_probe 4건, 부활 조건 4항). 판정은 **저장 cap-w essence basis 에만 scoped** 되며 신호 부재 판결이 아니다.

### next_probe (기전 진단에서 도출)

| # | 프로브 | 데이터 게이트 |
|---|---|---|
| **P1** | 상위 3건 dual-basis 재실측 — EW-유니버스 대비 + cap-tier(MEGA/MID) 분해. Chen-Welch 의 cap-w 2.537 → EW-uni 3.610 격차가 나머지 2건에도 있는지 | **열림 (실측 확인)** — 3건 전부 `sim_result.rds` + `bt_result.rds` + 10-component 계약 산출물(`04_holdings.csv` 포함) 보유. `canonical_screen_bt.R` 실존. ※`factor_engine.R` 은 부재라 엔진 재실행이 아니라 저장 holdings 기반 basis 재분석 경로 |
| **P2** | `oos_retention` v2(anchored 3분할 {55/65/75} 중앙값) 로 49건 재산출 — 저장 v1 단일절단 의심 | 열림 (essence_score `oos_stat_version="v2"`) |
| **P3** | 06-12~06-13 라벨분 45건 벤치 재베이스(07-02 IKS001→IKS200 수리 이전 vintage) — 현 dossier 우선순위 자체가 오정렬일 가능성 | 열림 |
| **P4** | FR_RCMA 20건 overlay A/B 결과 ↔ standalone backlog 상위 교차 — 겹치면 MDD 구조 사유 확증(overlay 라우팅), 안 겹치면 독립 알파원 | 열림 (overlay 큐 기존 배선) |

### 부활 조건 (INV-7, 경로-scoped)

(1) P1 에서 EW-uni PORT_t ≥ 2.95 ∧ cap-tier 분해가 MEGA 벤치 아티팩트를 시사 → dossier 착수 · (2) P2 에서 retention ≥ 0.50 밴드 진입 → 보강증거 2/3 심사 · (3) P3 재베이스 후 PORT_t ≥ 2.80 → 재순위 후 상위 재심 · (4) 비-return 신규 원천과의 결합에서 PORT_t 개선 관측.

### 배관/위생 잔여

| 항목 | 상태 |
|---|---|
| **main 병합** | **미이행 — 이것이 되기 전까지 main 부팅에 상태라인이 뜨지 않는다.** 브랜치는 main 을 병합해 뒀으므로 충돌 없이 들어간다 |
| worktree stash 1건 | `qepm/observability/events.jsonl` — main 판과 내용이 갈려 폐기하지 않고 보존. 본 작업 산출물 아님 |
| 50건 dual-basis 재실측 후 처분 확정 | 미착수 — `standalone_track_dispositions.json` 비어 있음 |
| `register_module()` catalog 승격 시 quarantine 행 회수 | 미수리 (본 과제 범위 밖, 별도 태스크) |
| `FR_RCMA` / `TURNOVER_REVIEW` 소비자 | 여전히 0. 큐가 `routes_without_consumer` 로 20건 상시 계상 중 |
| `register_module()` 이 screen_route 를 meta 에 기록 | 미이행 — 라벨이 원장에 도달하지 않아 `overlay_candidate_queue.R:70` 은 영구 빈 분기 |

---

## 8. 산출물

| 경로 | 성격 |
|---|---|
| `02_Infrastructure/portfolio/standalone_track_queue.R` | 신설 — 소비 배관 + 양방향 정합 스캔 |
| `06_Registry/standalone_track_queue.json` | 신설 — 생성물(미처분 50건 적재) |
| `06_Registry/standalone_track_dispositions.json` | 신설 — 처분 기록 원장(스키마 + 사용법, 현재 비어 있음) |
| `08_Tests/portfolio/test_standalone_track_queue.R` | 신설 — 위반 주입 17항목 |
| `08_Tests/hooks/run_all_hooks.sh` | 수정 — SUITES 등재 |
| `02_Infrastructure/ops/bootstrap.sh` | 수정 — §8j 상태라인 |
| `04_Research/01_reports/standalone_track_wiring_20260802.md` | 본 보고서 |

`05_Production/` · `01_Literature/` 무수정.
