import http from 'k6/http';
import { Counter } from 'k6/metrics';

// 测试B：同一个用户高并发重复下单 —— 所有 VU 共用同一个 token（在 bench 目录下运行）
const seckillOkCount = new Counter('seckill_success_count');
const tokens = JSON.parse(open('results/tokens.json'));
const BASE = __ENV.BASE || 'http://localhost:8085';
const VOUCHER_ID = 1;

export const options = {
  scenarios: {
    dup: { executor: 'constant-vus', vus: 20, duration: '5s' },
  },
};

export default function () {
  const token = tokens[0]; // 同一个用户
  const headers = { headers: { authorization: token } };
  const r1 = http.get(`${BASE}/voucher-order/seckill/token/${VOUCHER_ID}`, headers);
  let accessToken = '';
  try { accessToken = r1.json('data') || ''; } catch (e) {}
  const r2 = http.post(`${BASE}/voucher-order/seckill/${VOUCHER_ID}?accessToken=${accessToken}`, null, headers);
  try { if (r2.status === 200 && r2.json('success') === true) seckillOkCount.add(1); } catch (e) {}
}
