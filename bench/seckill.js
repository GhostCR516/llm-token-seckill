import http from 'k6/http';
import { check } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// 秒杀性能压测：取令牌 → 秒杀下单
// 用法（在 bench 目录下运行）: VUS=200 DURATION=60s k6 run seckill.js
// 需要先运行 gen_tokens.py 生成 results/tokens.json
const seckillOk = new Rate('seckill_success');
const seckillOkCount = new Counter('seckill_success_count');

const tokens = JSON.parse(open('results/tokens.json'));
const BASE = __ENV.BASE || 'http://localhost:8085';
const VOUCHER_ID = 1;
const VUS = Number(__ENV.VUS || 200);
const DURATION = __ENV.DURATION || '30s';

export const options = {
  scenarios: {
    seckill: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
};

export default function () {
  // 每个 VU 固定绑定一个用户 token（模拟不同用户）
  const token = tokens[(__VU - 1) % tokens.length];
  const headers = { headers: { authorization: token } };

  // 1. 获取秒杀令牌
  const r1 = http.get(`${BASE}/voucher-order/seckill/token/${VOUCHER_ID}`, headers, { tags: { step: 'issue_token' } });
  let accessToken = '';
  try { accessToken = r1.json('data') || ''; } catch (e) {}

  // 2. 发起秒杀
  const r2 = http.post(`${BASE}/voucher-order/seckill/${VOUCHER_ID}?accessToken=${accessToken}`, null, headers, { tags: { step: 'seckill' } });

  let ok = false;
  try { ok = r2.status === 200 && r2.json('success') === true; } catch (e) {}
  seckillOk.add(ok);
  if (ok) seckillOkCount.add(1);
  check(r2, { 'http 200': (r) => r.status === 200 });
}
