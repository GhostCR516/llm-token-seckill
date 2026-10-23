import http from 'k6/http';

// 第二组测试：缓存优化前后对比 —— 热点查询接口 GET /shop/{id}
// 用法: VUS=20 DURATION=60s k6 run query.js
const VUS = Number(__ENV.VUS || 20);
const DURATION = __ENV.DURATION || '60s';
const SHOP_ID = __ENV.SHOP_ID || 1;
const BASE = __ENV.BASE || 'http://localhost:8085';

export const options = {
  scenarios: {
    query: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
};

export default function () {
  http.get(`${BASE}/shop/${SHOP_ID}`);
}
