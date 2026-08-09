# 부활 감시 극성 범위 — 결정 요청 (2026-08-09)

**작성**: Q-Lead (`/cleaner` W32 증류 라운드 next_probe ④에서 파생)
**상태**: **결정 대기 — 구현하지 않음.** 두 안 모두 발화 동작을 바꾸므로 도훈 확인 후 진행.
**발단**: 모닝 큐가 보고한 "미배선 스텁 2건"과 카드 실측 4건이 어긋나 원인을 추적하다 확인.

---

## 1. 사실 (실측)

`02_Infrastructure/ops/failure_revival_monitor.R:173`

```r
if (!identical(d$polarity %||% "", "negative")) next
```

모니터는 `status ∈ {distilled, proposed}` 중 **`polarity == "negative"` 카드만** 순회한다.

| 구분 | 건수 |
|---|---|
| 순회 후보 (distilled + proposed) | 20 |
| ├ negative — 실제 감시 대상 | **9** |
| └ 비-negative (conditional 10 + positive 1) | **11** |
| 비-negative 중 `live_trigger` 보유 | **11 / 11 (전부)** |
| 비-negative 중 `revival_spec` 자동생성 보유 | 5 (원소 10) |

⇒ **비-negative 11건의 부활 조건은 평가되지 않는다.** 카운터 불일치(2 vs 4)의 원인도 이것이며,
큐 숫자가 맞고 카드 단순 스캔이 과다계상이었다.

이번 세션 신규 초안 5건 중 **4건이 conditional** 이라 모니터가 보는 것은 `DIST-AR-041` 하나뿐이다.

---

## 2. 두 해석 — 어느 쪽이냐에 따라 고칠 곳이 반대다

### 안 A — 설계다 (negative-only 가 의도)
근거: INV-7 "negative = 탐색지도, 재도전 대상". 부활(revival)은 **실패지식을 다시 꺼내는** 장치이므로
conditional/positive 는 대상이 아니다.

이 해석이면 결함은 **작성 측**이다: `distilled.R::.dist_author_revival_spec` 이 극성과 무관하게
revival_spec 을 자동 생성해, **절대 발화하지 않을 스텁**을 만들고 "미배선" 카운터를 오염시킨다.

- 고칠 곳: `draft_proposed` 경로에 극성 가드 — 비-negative 는 revival_spec 미생성(또는 `scope:"out_of_monitor"` 라벨).
- 부수: 명부 자동 스텁 append(`.dist_ensure_signal_registered`)도 함께 억제 — 지금은 쓰이지 않을 신호가 명부에 쌓인다.
- 되돌리기: 쉬움(생성 억제만, 기존 카드 무변경).

### 안 B — 결손이다 (범위가 좁다)
근거: conditional 카드의 live_trigger 상당수가 실질적으로 재도전 조건이다. 실례 —
`DIST-QPM-023` / `DIST-QPM-035` 의 트리거는 "estimated 근거가 canonical 로 재측정되면 재판정"인데,
이는 재부상 가치가 명백하고 negative 와 성격이 같다.

- 고칠 곳: `:173` 필터를 넓힘(예: `polarity ∈ {negative, conditional}`).
- 대가: **발화량 증가**. 현재 감시 9건 → 19건, revival_spec 원소도 함께 늘어난다.
- 되돌리기: 쉬움(필터 한 줄)이나, 그 사이 발화한 권고가 라운드를 유발했다면 되돌려도 소비는 남는다.

---

## 3. 권고

**안 B 가 맞아 보이나 확신하지 못한다.** conditional 트리거의 내용이 재도전 조건이라는 점은 실측이지만,
"모든 conditional 이 그렇다"는 아니다(1건은 positive 이고, conditional 중 일부는 단순 조건부 서술일 수 있다).

**중간 경로 제안**: 필터를 넓히되 **발화 등급을 나눈다** — negative 는 지금처럼 "재도전 권고",
conditional 은 "재검토 알림"으로 분리 표시. 발화량 증가가 권고의 신호대잡음을 떨어뜨리는 것을 막는다.
이 안은 `:173` 한 줄 + 출력부 라벨 분기로 끝난다.

---

## 4. 어느 안이든 함께 걸 검증 (양방향 의무)

1. **양성**: 조건이 참인 카드가 실제로 발화하는가 (오늘 `dart_insider_present` 3건이 선례 — 동기화 후 0→3건).
2. **음성**: 조건이 거짓이거나 신호가 pending 인 카드는 발화하지 않는가
   (오늘 `registry_present` 3건이 pending 유지로 이 축을 지켰다).
3. **항진명제 금지**: 넓힌 뒤 발화 건수가 감시 대상 수와 같아지면(=전건 발화) 그건 신호가 아니라 상수다.
   `registry_present` 를 `file_exists` 로 등록하지 않은 이유와 같은 축 — `06_Registry/revival_signals.json`
   해당 스텁 note 에 근거 기록됨.

---

## 5. 참조
- 라운드 마커: `CLEANER_W32_pending5axis_drain_20260809` (`capability_established`)
- 같은 날 동일 계통 3건: AST `compiler_incompatible_nodes`(존재하나 미노출) ·
  `dart_insider_present`(신호 active 인데 카드 pending, 26일 무발화) · 본 건(조건은 있으나 순회 밖)
- 수리 완료분: `distilled.R::sync_revival_spec_status()` (명부↔카드 양방향 동기화, 승격 3 · 강등 0)
- `04_Research/01_reports/weekly/weekly_digest_20260809.md`
