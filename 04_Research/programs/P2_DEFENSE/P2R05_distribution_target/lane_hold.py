# -*- coding: utf-8 -*-
"""충실구현 레인 보류 · 자동 재개 — P2R05 GPU 창(도훈 10-18 17:2x 선택 'THGNN 끝난 뒤 레인 보류').
P2R03 lane_pause.py 와 같은 레인 자기 스위치(06_Registry/reinforce_auto_config.json::replication_lane.enabled)를 원자적으로 바꾼다.
- pause: 스위치만 끈다. 레인 틱은 스위치가 꺼져 있으면 claim 을 건드리지 않고 바로 물러난다(rf_replication_auto.sh 게이트 halt_disabled) —
  이미 돌고 있는 작업(2601.04602 THGNN 측정)은 끝까지 간다. 새 논문 · 새 GPU 작업만 시작하지 않는다.
- wait-resume: P2R05 캐시 워밍 센티널(분위 261개월 + 재시드 261개월 학습 끝 — 성공 · 실패 무관 = GPU 가 비었다)이 보류 시각 뒤에 생기거나
  마감에 닿으면 스위치를 켠다. 5분 간격 확인.
P2R05 측정 절차와 무관(사전등록 고정 대상 아님 — GPU 배분만).
사용: python lane_hold.py pause "<사유>" | resume "<사유>" | wait-resume <센티널 경로> <마감 YYYY-mm-ddTHH:MM>"""
import datetime as dt, io, json, os, sys, tempfile, time

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CFG = os.path.join(ROOT, "06_Registry", "reinforce_auto_config.json")


def _set(enabled, note):
    with io.open(CFG, "r", encoding="utf-8") as f:
        c = json.load(f)
    r = c.setdefault("replication_lane", {})
    r["enabled"] = bool(enabled)
    now = dt.datetime.now().strftime("%Y-%m-%dT%H:%M")
    if enabled:
        r["resumed_at"] = now; r["resumed_note"] = note
    else:
        r["paused_at"] = now; r["paused_note"] = note
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CFG), suffix=".tmp")
    with io.open(fd, "w", encoding="utf-8", newline="\n") as f:
        json.dump(c, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, CFG)
    print("[lane_hold] replication_lane.enabled = %s · %s · %s" % (enabled, now, note), flush=True)


def _paused_at():
    with io.open(CFG, "r", encoding="utf-8") as f:
        r = (json.load(f).get("replication_lane") or {})
    return dt.datetime.strptime(r["paused_at"], "%Y-%m-%dT%H:%M") if r.get("paused_at") else None


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "pause":
        _set(False, sys.argv[2])
    elif cmd == "resume":
        _set(True, sys.argv[2])
    elif cmd == "wait-resume":
        sentinel, deadline = sys.argv[2], dt.datetime.strptime(sys.argv[3], "%Y-%m-%dT%H:%M")
        t0 = _paused_at() or dt.datetime.now()
        print("[lane_hold] 대기 시작 — 센티널 %s(보류 %s 뒤 생성) 또는 마감 %s" % (sentinel, t0, deadline), flush=True)
        while True:
            if os.path.exists(sentinel) and dt.datetime.fromtimestamp(os.path.getmtime(sentinel)) >= t0:
                _set(True, "도훈 10-18 'THGNN 끝난 뒤 레인 보류' → P2R05 캐시 워밍 끝(센티널 %s) — 자동 재개" % os.path.basename(sentinel)); break
            if dt.datetime.now() >= deadline:
                _set(True, "도훈 10-18 'THGNN 끝난 뒤 레인 보류' → 마감 도달 자동 재개(P2R05 워밍 미완 — 세션 확인 필요)"); break
            time.sleep(300)
    else:
        sys.exit("usage: lane_hold.py pause|resume <note> | wait-resume <sentinel> <deadline>")
