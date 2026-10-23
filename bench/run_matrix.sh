#!/bin/zsh
# 第一组测试：秒杀接口性能矩阵（快速版）
# 并发级别 × 3 轮重复；每轮：快速重置（仅 Redis 键 + DB 库存列）→ 预热 15s → 测量 60s
# 订单表不在轮次间清空，Kafka 消费在后台持续进行（对 Redis 路径的测量无影响）
# 需先生成 bench/results/tokens.json（见 gen_tokens.py），并在 bench 目录下运行
set -u
BENCH="$(cd "$(dirname "$0")" && pwd)"
PREFIX=${PREFIX:-ghost}   # 与后端 -Dprefix.distinction.name 保持一致
mkdir -p $BENCH/results
cd $BENCH

fast_reset() {
  redis-cli del "${PREFIX}-seckill:stock:{1}" "${PREFIX}-seckill:user:{1}" "${PREFIX}-seckill:trace:log:{1}" >/dev/null
  docker exec mysql mysql -uroot -proot -e "UPDATE hmdp_1.tb_seckill_voucher_0 SET stock=1000000 WHERE voucher_id=1;" 2>/dev/null
}

for L in 50 100 200 400; do
  for R in 1 2 3; do
    fast_reset
    VUS=$L DURATION=15s k6 run -q seckill.js > /dev/null 2>&1   # 预热
    fast_reset
    VUS=$L DURATION=60s k6 run --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)" --summary-export=results/matrix_${L}_r${R}.json seckill.js > results/matrix_${L}_r${R}.txt 2>&1
    echo "done L=$L R=$R : $(grep 'http_reqs' results/matrix_${L}_r${R}.txt | head -1)"
  done
done
echo "=== MATRIX ALL DONE ==="
