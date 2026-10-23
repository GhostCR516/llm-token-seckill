#!/usr/bin/env python3
"""批量注册并登录用户，生成压测用 token 列表（输出到 bench/results/tokens.json）"""
import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = os.environ.get("BASE", "http://localhost:8085")
N = int(os.environ.get("N", "2000"))  # 生成 N 个用户 token
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "tokens.json")

def post(url, data=None):
    body = json.dumps(data).encode() if data is not None else b""
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def make_token(i):
    phone = f"138{i:08d}"
    code = post(f"{BASE}/user/code?phone={phone}")["data"]
    return post(f"{BASE}/user/login", {"phone": phone, "code": code})["data"]

with ThreadPoolExecutor(max_workers=20) as pool:
    tokens = [t for t in pool.map(make_token, range(2, N + 2)) if t]

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(tokens, f)
print(f"generated {len(tokens)} tokens -> {OUT}")
