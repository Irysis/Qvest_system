---
name: book-rebalance
description: BOOK 코드별 리밸런싱 표준 절차 (v10) — book_id 로 사양을 찾아 사전점검(소비면 신선도·생산자 배선·오버레이 생존) → 러너 실행 → 사후검증 → BOOK 트래킹 → 텔레그램. 전략마다 필요한 코드·데이터가 다르므로 기억이 아니라 사양이 절차를 정한다. 사양 = 02_Infrastructure/book/rebalance_spec.json.
---

# BOOK 리밸런싱 (book_id 단위 표준 절차)

**발효**: 2026-08-30 (도훈 지시 — "BOOK 코드별로 리밸런싱 표준화. 각 전략에 필요한
코드와 데이터들이 모두 다를 거잖아").

**해결하는 문제**: 지금까지 리밸은 사람이 기억으로 러너를 호출했다. 그래서 같은 날
세 가지 침묵 결함이 한꺼번에 드러났다 — ①다운로드는 됐는데 적재가 안 돼 컨센서스가
한 달 정지(게이트 둘 다 통과, 20종 중 9종 교체) ②AE 신호 생산자에 호출자가 0건이라
한 달 정지(소비자가 직전 달을 조용히 재사용) ③m4 BOCPD 팔이 271개월 내내 0회 발화.

셋의 공통 기전은 하나다 — **잴 것을 안 재고 재기 쉬운 것을 쟀다.**

## 원칙 3줄

1. **신선도는 소비면에서 잰다.** 원천 상태파일·mtime·"러너가 OK를 찍었다"는 근거가 아니다.
   실제로 읽히는 파케이의 `max(Date)`를 축마다 따로 잰다 — 한 축이 신선하면 합산 지표는
   신선해 보인다(앵커는 주가 축이 채운다).
2. **미측정은 미달이 아니다.** 부재 = MISSING · 판독불가 = UNREADABLE 로 갈라 보고한다.
   '못 읽음'과 '낡음'이 같은 색이면 다음 사람이 원인을 원천이 아니라 게이트에서 찾는다.
3. **경고 없음은 살아 있다는 증거가 아니다.** 오버레이 팔마다 역사 발화율을 센다.
   `expect_alive` 인데 0회면 그 팔은 죽은 것이다.

## 절차

### 0. 사양 확인

정본 = `02_Infrastructure/book/rebalance_spec.json` (schema `book_rebalance_spec_v1`).
book_id 별로 **러너 · 입력(소비면 경로·신선도 관용·생산자·배선 여부) · 오버레이 팔 ·
사후검증**을 선언한다. 사양에 없는 book_id 는 리밸하지 않는다 — 먼저 사양을 적는다.

> ★사양을 `06_Registry/book/` 에 두지 말 것. 그 폴더는 **등록 정본** 전용이고
> `book_write_guard.sh` 가 writer 경유만 허용한다(등록 자격 검증 우회 차단).

### 1. 사전점검 (필수 — 건너뛰지 않는다)

```bash
.venv_qvest_ml/Scripts/python.exe 02_Infrastructure/book/book_rebalance_preflight.py \
  --book-id BOOK_0001 --as-of 2026-09-01
```

세 축을 잰다:

| 축 | 재는 것 | 실패 시 |
|---|---|---|
| A | 입력 신선도 — **소비면** `max(Date)` vs as_of 직전 영업일 | STALE/MISSING/UNREADABLE → **BLOCK** |
| B | 생산자가 리밸 경로에 **배선**돼 있는가 | 배선X 는 표시 + 선행 실행 명령 출력 |
| C | 오버레이 팔의 **역사 발화율** | DEAD(0회) / REVIVED(구판 부활) → 경고 |

`GO` 가 아니면 러너를 돌리지 않는다. 출력이 각 입력의 **선행 실행 명령**을 그대로 준다.
`--json` 으로 기계 판독.

⚠축 C 는 차단하지 않는다(등급 축 변경은 도훈 권한). 다만 **보고 의무**다 —
DEAD 팔이 있는 채로 리밸을 돌렸으면 그 사실을 결과와 함께 말한다.

### 2. 러너 실행

사양의 `runner.cmd` 를 그대로 쓴다(사전점검 출력 마지막 줄에 찍힌다).
러너는 자체 게이트를 가진다 — BOOK_0001 = Gate A(원천 수신) · Gate B(팩터DB 앵커 내용) ·
Gate D(하드제약·전월 지문). 게이트가 막으면 **사유부터 보고**하고 우회하지 않는다.

### 3. 사후검증

사양 `post_checks` 를 산출물로 재도출한다(러너 로그의 OK 를 인용하지 말 것 — 진술은
증거가 아니다). 최소: Σw=1 · 실질보유 ≤25 · long-only · 유동성 · **비중 지문이 전월과
다를 것**(조용한 재출력 검출) · manifest.as_of 일치.

### 4. BOOK 트래킹 갱신

```r
source("02_Infrastructure/book/book_registry.R")
update_book_tracking("BOOK_0001", list(as_of=..., last_nav_date=..., weights_fingerprint=...,
                                       regime=..., invested=..., cash=..., n_equity=...,
                                       gate_d="PASS", data_vintage="...", artifacts="..."))
```

writer 경유만. `06_Registry/book/**` 직접 편집은 훅이 막는다.

### 5. 텔레그램

`tg_agent_brief(agent="Book", title="[BOOK] 트래킹 — {book_id} …")`.
표제 정본 = `qvest-telegram` SKILL §5.6b. 본문에 **데이터 종점**과 **DEAD 오버레이 유무**를
반드시 적는다.

## 신규 BOOK 등재 시 (사양 작성 규약)

전략마다 코드·데이터가 다르므로, 등재와 **동시에** 사양을 쓴다. 최소 항목:

- `runner`: cmd(플레이스홀더 `{as_of}`·`{as_of_compact}`·`{sig_ym}`) · 산출 경로 · 게이트 목록
- `inputs[]`: **소비면 경로**(생산 원천이 아니라 전략이 실제로 `read_parquet` 하는 파일) ·
  `date_col` · `mode`(`data` 일단위 lag / `decision` as_of 행 존재 / `anchor` sig_date 일치) ·
  `max_lag_days` · `producer` · `wired_in_runner` · 배선 없으면 `manual_cmd`
- `overlays[]`: `panel` · `fire_expr`(pandas eval) · `expect_alive`
  — 죽은 팔을 알면서 두는 경우 `expect_alive:false` + `note` 로 **회귀 감시**로 전환
- `post_checks[]`

`max_lag_days` 는 **실측으로 재단**한다. 두 양을 갈라야 한다 — 원천의 정상 발행지연과
캐시의 낡음은 다르다(FRED 주간계열 정상 7d vs 조기 생성 핀 28~35d → 문턱 14).

## 하지 않는 것

- 사전점검 건너뛰고 러너 직행 · BLOCK 을 무시하고 강행 · 게이트 사유 우회
- 러너 로그의 "OK"를 사후검증으로 인용 · `06_Registry/book/**` 직접 편집
- DEAD 오버레이를 조용히 넘기기 · 오버레이 문턱 임의 재보정(등급 축 = 도훈 권한)

## 참조

`02_Infrastructure/book/rebalance_spec.json`(사양) ·
`02_Infrastructure/book/book_rebalance_preflight.py`(검사기) ·
`08_Tests/book/test_book_rebalance_preflight.py`(양방향 10축) ·
`02_Infrastructure/book/book_registry.R`(writer) · `.claude/commands/book.md` · `CLAUDE.md`
