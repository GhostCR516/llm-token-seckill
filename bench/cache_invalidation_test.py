#!/usr/bin/env python3
"""第六组测试：缓存失效跨实例传播延迟（仪器化版）

计时口径：
  T0   = 更新请求（主实例 POST /voucher/update/seckill）发出的时刻
  T1   = 从实例 GET /voucher/get 首次返回新值的时刻（响应完成）
  可见性延迟 = T1 - T0，是「端到端用户可见一致性窗口」上界：
  覆盖 DB 提交 + Kafka 异步发布(在途) + 消费者拉取 + 实例本地 Caffeine L1 失效
  + Redis L2 删除 + 观测请求回源重建，轮询粒度 ≈ 单次 GET 耗时（本机 ~2-4ms）。
  注意生产者 sendPayload 返回 CompletableFuture 且未 .get()，发送相对更新响应异步。

用法：python3 cache_invalidation_test.py [主实例] [从实例] [轮数]
前提：两个实例均已启动（默认 8085 / 8086），且 voucher 1 存在 minLevel 字段。
"""
import json
import sys
import time
import urllib.request

A_BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8085"
B_BASE = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:8086"
RUNS = int(sys.argv[3]) if len(sys.argv) > 3 else 2


def post(url, data):
    body = json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=10) as r:
        resp = json.load(r)
    return t0, time.time(), resp


def get_minlevel(base):
    _, _, resp = post(f"{base}/voucher/get", {"voucherId": 1})
    assert resp.get("success"), resp
    return int(resp["data"]["minLevel"])


results = []
for run in range(1, RUNS + 1):
    cur = get_minlevel(A_BASE)
    get_minlevel(B_BASE)  # 让从实例 L1 也持有同一旧值
    new = 2 if cur == 1 else 1

    t_req_start, t_req_end, resp = post(
        f"{A_BASE}/voucher/update/seckill", {"voucherId": 1, "minLevel": new})
    assert resp.get("success"), resp

    polls = 0
    while True:
        polls += 1
        t_seen, _, r = post(f"{B_BASE}/voucher/get", {"voucherId": 1})
        if int(r["data"]["minLevel"]) == new:
            break
        if time.time() - t_req_end > 30:
            raise SystemExit(f"run{run}: 30s 内未观测到新值")

    results.append({
        "run": run,
        "flip": f"{cur}->{new}",
        "visibility_from_req_start_ms": round((t_seen - t_req_start) * 1000, 1),
        "visibility_from_resp_ms": round((t_seen - t_req_end) * 1000, 1),
        "polls": polls,
    })
    print(results[-1], flush=True)

print(json.dumps(results, ensure_ascii=False))
