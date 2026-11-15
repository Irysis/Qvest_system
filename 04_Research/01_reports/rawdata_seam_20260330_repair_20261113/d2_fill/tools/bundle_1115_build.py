"""적용 대기 묶음(11-15) 명세 만들기 — 등록부 · RAWDATA 쓰기 없음. 적용할 때 다시 돌려 값을 새로 잰다.

묶음 = 값이 바뀌는 3행(A012470 1998-07-13 · A008080 2012-01-12 · 2012-11-30 — 시총 기준 · 주식 수 불변) +
       고정 5행((가) 유가증권 이전상장 첫날 — 저장값 비트 그대로 · 규칙이 바뀌어도 시총 기준으로 채워지지 않게).
(나) 2행(A003580 · A013520)은 등록부에 넣지 않는다(현행 유지 — 단절 전 체결 0 이라 확인값이 아니다).
도훈 결정 RAWDATA-7ROWS-CORPACTION-REQUERY-20261115 — 적용은 한 묶음(판 원장 1줄).

사용: python bundle_1115_build.py <SP = ca7_rejudge_rows.csv 가 있는 폴더> [RAWDATA.parquet]
출력: d2_fill/pending_bundle_20261115.json
"""
import csv, json, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
import pandas as pd
import pyarrow.parquet as pq

SP = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else ".cache/RAWDATA.parquet"
OUT = Path(__file__).resolve().parent.parent / "pending_bundle_20261115.json"
DEC = "RAWDATA-7ROWS-CORPACTION-REQUERY-20261115"

# 값이 바뀌는 3행 — (날짜 · 종목 · 적용 전 저장값(이 값이 아니면 멈춘다) · 근거)
CHANGE = [
    ("1998-07-13", "A012470", -0.9945456528853496,
     "퀀티 수정 계수 착시 — 단절은 1998-07-11 토요일이고 RAWDATA 에 토요일 행이 없어 이 행 = 토 · 월 두 세션. 이벤트 뒤 주식 수로 나눈 이벤트 전 시총이 "
     "1998-01~07-10 129일 모두 5원 호가 단위 · 수정 계수(수정 종가 ÷ 그 원주가) 152.78 로 일정 · 단절 앞뒤 시총 최대공약수 24,550,000 같음 → 주식 수 그대로 · "
     "보유자 수익 = 시총 기준(세션별 −8.3% · −9.1% 모두 당시 하루 제한폭 12% 안). 퀀티 재조회(11-15 지금 판)도 같은 단절. 재현 = d2_fill/tools/requery_1115_check.py · list9_check.py. "
     "측정 축 밖(2000 전 · 동전주)."),
    ("2012-01-12", "A008080", 0.5,
     "상장폐지 실질심사 거래정지(2011-10-27 ~ 2012-01-11 · DART 실질심사 대상 결정 11-16 → 상장폐지기준 미해당 2012-01-11) 뒤 재개 첫날. "
     "정지 전(10-04~10-26) 시총 최대공약수 82,088,125 · 재개 뒤(01-12~01-20) 410,440,625 = 앞 × 5 · DART 2011-10 ~ 2012-02 증자 · 감자 · 전환 공시 없음 → 주식 수 그대로 · "
     "보유자 수익 = 시총 기준. 저장 생비율 +50%(수정주가 2 → 3원)는 반올림 착시. 제한폭 ±15% 밖 = 재개일 기준가(설정 주석 '재개일은 수동 등록부'). "
     "재현 = d2_fill/tools/list9_check.py · list9_dart.R. 측정 축 밖(동전주)."),
    ("2012-11-30", "A008080", -0.5,
     "단절 앞뒤 시총 최대공약수 92,446,775 같음 · DART 2012-11 증자 · 감자 공시 없음 → 주식 수 그대로 · 보유자 수익 = 시총 기준 = 하한가 −15% 정확히. "
     "저장 생비율 −50%(수정주가 2 → 1원)는 반올림 착시. 채움 규칙 abs(mc) <= tol(seam_scale_guard.R)이 부동소수점(−0.15000000000000002)으로 경계에서 떨어져 등록부로 넣는다. "
     "재현 = d2_fill/tools/list9_check.py. 측정 축 밖(동전주)."),
]

rj = list(csv.DictReader(open(f"{SP}/ca7_rejudge_rows.csv", encoding="utf-8")))
pins = [r for r in rj if r["group"] == "가"]
keep = [r for r in rj if r["group"] != "가"]
assert len(pins) == 5 and all(r["verdict"].startswith("확정") for r in pins), "ca7_rejudge 결과가 (가) 확정 5행이 아니다 — 다시 판정할 것"

keys = [(d, c) for d, c, *_ in CHANGE] + [(r["date"], r["code"]) for r in pins]
t = pq.read_table(RAW, columns=["Date", "Ticker", "Size", "Ret"], filters=[("Ticker", "in", sorted({c for _, c in keys}))]).to_pandas()
t["Date"] = pd.to_datetime(t["Date"])
t = t.sort_values(["Ticker", "Date"]).reset_index(drop=True)


def row_pair(d, c):
    s = t[t.Ticker == c].reset_index(drop=True)
    i = int(s.index[s.Date == pd.Timestamp(d)][0])
    assert i > 0, f"{c} {d} 첫 행"
    return s.iloc[i - 1], s.iloc[i]


now = datetime.now(timezone(timedelta(hours=9))).isoformat(timespec="seconds")
entries_change, entries_pin = [], []
for d, c, before, ev in CHANGE:
    p, q = row_pair(d, c)
    assert float(q.Ret) == before, f"{c} {d} 저장값 {float(q.Ret)!r} ≠ 적용 전 기대 {before!r} — RAWDATA 가 바뀌었다(멈춤)"
    mc = float(q.Size) / float(p.Size) - 1
    entries_change.append(dict(Date=d, Ticker=c, Ret=round(mc, 10), method="mcap_ratio_share_count_constant",
                               evidence=f"{ev} 시총 {float(p.Size):,.0f} → {float(q.Size):,.0f}.", decision=DEC, recorded_at=now,
                               ret_before=before))
for r in pins:
    p, q = row_pair(r["date"], r["code"])
    stored = float(q.Ret)
    assert abs(stored - float(r["stored"])) <= 5e-8, f"{r['code']} 저장값이 재판정 때와 다르다"
    base_txt = (f"새 시장 기준가 대비 {float(r['vs_base']) * 100:+.2f}% = 뒤 세션 연속 제한가 폭({float(r['lim_emp']) * 100:.2f}%)과 같다"
                if r["limit_ok"] == "True" else
                f"퀀티 기준가 = 전일 종가 그대로라 상장일 기준가를 담지 않은 것으로 본다 — 뒤 세션 연속 제한가 폭({float(r['lim_emp']) * 100:.2f}%)으로 "
                f"거꾸로 셈한 기준가 {int(r['base_implied']):,}원이면 그날도 제한가")
    entries_pin.append(dict(
        Date=r["date"], Ticker=r["code"], Ret=stored, method="kospi_transfer_listing_holder_ratio",
        evidence=(f"유가증권시장 상장 첫날(퀀티 시장구분 {r['market']} 이날) · 발행주식수 {r['issued_change']}(단절 {r['days_issue_to_break']}일 전 · 새 주식 = 상장 뒤 주식의 "
                  f"{float(r['new_share_frac']) * 100:.1f}%) 뒤 이날 상장주식수가 발행주식수로 · 창 안 구시장 기준가 = 전일 종가(권리락 없음 = 기존 주주 배정 · 무상 아님) → "
                  f"사건 = 이전상장 · 공모. 등록부 규칙 '이전상장 · 일반공모 = 생비율' — 주식은 1:1 로 옮겨가고 신주가 시총을 부풀린다"
                  f"(시총 기준 {float(r['mc_listed']) * 100:+.2f}% 는 보유자 수익 아님). 퀀티 수정 계수 앞뒤 같음 → 저장 수정주가 비율 = 원주가 비율 "
                  f"{float(r['raw']) * 100:+.3f}%(반올림 차 {abs(stored - float(r['raw'])):.1e}). {base_txt}. "
                  "저장값 비트 그대로 — 등록부 강제가 바꾸는 값이 없고, 규칙이 바뀌어도 시총 기준으로 채워지지 않게 고정한다. "
                  "근거 = 리프레시 세션 퀀티 재조회 11-15(일별 18항목 · 이음매 노트) · d2_fill/tools/ca7_rejudge.py. 측정 축 밖(2000 전)."),
        decision=DEC, recorded_at=now, ret_before=stored))

spec = dict(
    schema="ret_fill_bundle_pending_v1", decision=[DEC, "RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114"], status="pending", built_at=now,
    rerun_before_apply="적용 직전에 이 스크립트를 다시 돌려 값을 새로 잰다(적용 전 저장값 단정이 멈춤 장치)",
    apply_when=("다음 범위 all 팩터 DB 수리에 얹는다 — 11-15 확정(오케스트레이터 회신 · 도훈 '지금 적용' 미선택). 지금 따로 적용하면 판 원장 범위에 달 구분이 없어 "
                "완료 전 측정이 모두 낡음이 된다. 종가 수리는 없어졌으므로(QW-FILE-IS-REFERENCE-20261115) 싣는 수리는 다른 사유의 범위 all 수리다(C6 수리가 RAWDATA 를 바꾸면 그것도)."),
    cautions=[
        "C6(RAWDATA-PRELISTING-C6-20261115 · 도훈 결정 대기)와 맞물린다: 고정 2행(A016560 1996-11-19 · A027840 1997-11-25 — 외감 → 유가증권)과 기존 등록부 13행"
        "(코넥스 → 코스닥 8 · 장외 → 코스닥 5)은 상장 전 이력 바로 다음 첫날이다. C6 를 RAWDATA 상장 전 행 삭제로 풀면 이 행들이 종목의 첫 행이 되고, "
        "감사기 등록부 강제(rawdata_seam_audit.R registry_fix — 저장값이 NA 여도 등록부 값을 쓴다)가 상장 첫날에 −52 ~ +11% 가짜 수익을 써 넣는다"
        "(경보 없음 · 로그 '[SEAM_FILL] 수동 등록부 강제 n행'뿐) → 그 수리에서는 이 15행을 등록부에서 빼고 고정 2행은 싣지 않는다. "
        "유니버스 거르기(RAWDATA 그대로)로 풀면 바꿀 것 없음. 이 스크립트의 row_pair 는 묶음 8행이 첫 행이면 멈추지만 등록부 13행은 검사 밖이다 "
        "(11-15 점검 = 등록부 14 + 고정 5 = 19행 모두 앞 이력 94 ~ 2,587행 · 첫 행 0).",
    ],
    procedure=[
        "① 등록부 06_Registry/ret_fill_registry.json entries 끝에 entries_change 3 + entries_pin 5 추가(ret_before 열은 빼고 · 다른 바이트 보존)",
        "② writer 잠금 아래 seam_repair_locked.sh --apply — 23:30 전 또는 밤 로그 '[lock] 데이터 갱신 완료' 뒤 · 07:10 아침 체인과 겹치지 않게",
        "③ 적용 뒤 대조 = Ret 3행만 바뀜(고정 5행은 등록부 강제 0 · 비트 동일) · 전 열 대조(d2b_diff.R)",
        "④ 파생 = FF 요인 재빌드 · 팩터 DB Ret 모듈 부분 재계산(명세에 xlsx_fund 포함 — 빠지면 밸류 · 성장 XF 채움 행 소실) · IC · 결합용 뷰 · 이번 달",
        "⑤ 판 원장 06_Registry/factor_db_vintage.json 1줄(진행 중 = JSON null · 끝나면 completed_at) · 1계층 세션 통지(τ_D 규칙 — IS 판정 · 칸 수 · 경로만)",
    ],
    entries_change=entries_change, entries_pin=entries_pin,
    not_registered=[dict(Date=r["date"], Ticker=r["code"], Ret_stored=float(r["stored"]), verdict=r["verdict"],
                         reason="이미 발행된 주식의 상장(발행주식수 그대로) + 배당락 — 빠진 조정 없음. 단절 전 체결 0(호가만)이라 체결 기준 확인값이 아니어서 등록부에 넣지 않는다(현행 유지).")
                    for r in keep],
)
OUT.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print(f"{OUT} · 값 변경 {len(entries_change)} · 고정 {len(entries_pin)} · 등록 안 함 {len(keep)}")
for e in entries_change:
    print(f"  변경 {e['Date']} {e['Ticker']} {e['ret_before']!r} → {e['Ret']!r}")
for e in entries_pin:
    print(f"  고정 {e['Date']} {e['Ticker']} {e['Ret']!r}")
