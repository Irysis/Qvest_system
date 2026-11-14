"""판 원장 D2 항목의 note · evidence 만 바꾼다(다른 바이트 보존 · LF). argv: ledger_path"""
import json, sys
path = sys.argv[1]
raw = open(path, "rb").read()
assert b"\r\n" not in raw
txt = raw.decode("utf-8")
d = json.loads(txt)
EID = "RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114"
e = [x for x in d["entries"] if x["id"] == EID]
assert len(e) == 1 and e[0]["completed_at"] == ""
old_note, old_ev = e[0]["note"], e[0]["evidence"]
new_note = (
    "RAWDATA 수익률 단절 자리를 채웠다(writer 잠금 · seam_repair_locked.sh --apply · 적재기 규칙 e2d1df053 + 수동 등록부 강제). "
    "① 11-14 17:31 — 시가총액 기준 실수익(그날 시총 ÷ 전날 시총 − 1 · 날짜별 가격제한폭 2015-06-15 전 ±15% · 뒤 ±30% 안) 159행. "
    "② 11-14 18:22 정정 — DART 사건 종류 + 거래소 원주가(네이버 모바일 일별 시세)로 다시 확인해 10행을 바꿨다: "
    "코넥스 → 코스닥 이전상장 첫날 5행(일반공모 신주가 시총을 부풀려 시총 기준이 틀렸다 → 생비율 = 보유자 수익 · A197210 A220100 A214610 A107640 A250030) · "
    "장외 → 코스닥 신규 상장 첫날 4행(퀀티가 상장 뒤 가격만 이후 사건으로 수정해 생비율이 깨졌다 → 거래소 첫 종가 ÷ 장외 마지막 종가 · A042000 A046120 A053580 A062970) · "
    "1998-01-05 A012170(토요일 행 결손 → 네이버 수정주가 같은 구간). 확인한 값 14행 = 06_Registry/ret_fill_registry.json(적재기가 매번 강제). "
    "적용 전(11-14 아침) 대비 Ret 이 바뀐 행 = 155(03-30 이음매 71 · A008080 반올림 75 · 장외 → 상장 첫날 4 · A250030 · A012170 · 2000 전 3) · 이전상장 4행은 원래 값으로 돌아갔다. "
    "못 채운 것 = 원천 내부 단절 10행(2000 전 8 · A008080 2원 반올림 2 · 측정 축 밖) · 첫 관측 11행(앵커 없음 = 빈칸이 맞다). "
    "진행 중 = 팩터 DB(Ret · 연속 가격을 쓰는 10모듈 · 전 기간 · 18:28 재시작 — 17:38 실행은 정정 전 입력이라 멈췄다) · IC · 결합용 뷰 재계산 끝에 completed_at 을 채운다 — 그때까지 범위 all 의 측정은 낡음."
)
new_ev = (
    "04_Research/01_reports/rawdata_seam_20260330_repair_20261113/README.md §10 · .cache/rawdata_seam_audit/audit_after_repair_20261114_182246.json · "
    ".cache/rawdata_pre_seamguard_20261114.parquet(적용 전 사본) · 06_Registry/ret_fill_registry.json(14행 · 행마다 method · evidence) · "
    "RAWDATA md5 506a0e13736d(18:22) · FF 월간 내용 md5 3dd806e4f9ff(18:28)"
)
for o, n in ((old_note, new_note), (old_ev, new_ev)):
    eo, en = json.dumps(o, ensure_ascii=False), json.dumps(n, ensure_ascii=False)
    assert txt.count(eo) == 1, "old string not unique"
    txt = txt.replace(eo, en)
d2 = json.loads(txt)
e2 = [x for x in d2["entries"] if x["id"] == EID][0]
assert e2["note"] == new_note and e2["evidence"] == new_ev and len(d2["entries"]) == len(d["entries"])
assert [x for x in d2["entries"] if x["id"] != EID] == [x for x in d["entries"] if x["id"] != EID]
open(path, "wb").write(txt.encode("utf-8"))
print("updated", EID)
