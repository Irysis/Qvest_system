# -*- coding: utf-8 -*-
"""충실구현 레인 일시 정지 · 재개(도훈 10-17 22:2x '레인 잠깐 멈추고 GPU P2R03에 몰아줘') — 레인 자기 스위치
06_Registry/reinforce_auto_config.json::replication_lane.enabled 를 원자적으로 바꾼다(형식 유지 · 2칸 들여쓰기 · 한글 그대로).
P2R03 측정 절차와 무관(사전등록 고정 대상 아님 — GPU 배분만).
사용: python lane_pause.py pause "<사유>" | resume "<사유>" | wait-resume <results_dir> <deadline YYYY-mm-ddTHH:MM>"""
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
    print("[lane_pause] replication_lane.enabled = %s · %s" % (enabled, now), flush=True)


def _rx0_ok(res):
    p = os.path.join(res, "P2R03_E2_RX0.json")
    try:
        with io.open(p, "r", encoding="utf-8") as f:
            return json.load(f).get("ok") is True
    except Exception:
        return False


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "pause":
        _set(False, sys.argv[2])
    elif cmd == "resume":
        _set(True, sys.argv[2])
    elif cmd == "wait-resume":
        res, deadline = sys.argv[2], dt.datetime.strptime(sys.argv[3], "%Y-%m-%dT%H:%M")
        print("[lane_pause] 대기 시작 — P2R03_E2_RX0 측정 끝(DNN 재학습 = GPU 몫) 또는 마감 %s" % deadline, flush=True)
        while True:
            if _rx0_ok(res):
                _set(True, "도훈 10-17 22:2x 'GPU P2R03에 몰아줘' 일시 정지 → P2R03 E2 RX0 측정 끝(DNN 새 epoch 재학습 완료 · 이후 칸은 캐시) — 자동 재개"); break
            if dt.datetime.now() >= deadline:
                _set(True, "도훈 10-17 22:2x 'GPU P2R03에 몰아줘' 일시 정지 → 마감 도달 자동 재개(P2R03 E2 RX0 미완 — 세션 확인 필요)"); break
            time.sleep(300)
    else:
        sys.exit("usage: lane_pause.py pause|resume <note> | wait-resume <results_dir> <deadline>")
