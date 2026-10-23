#!/bin/zsh
# 重置秒杀测试状态：等 Kafka 消费完 -> 清订单表 -> 重置库存 -> 清 Redis 键
# 用法: reset_seckill.sh [库存数量，默认 1000000]
# PREFIX 需与后端 -Dprefix.distinction.name 保持一致
STOCK=${1:-1000000}
PREFIX=${PREFIX:-ghost}

# 1. 等 Kafka 消费组追平（最长 20 分钟）
for i in $(seq 1 600); do
  lag=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group create_voucher_order 2>/dev/null | awk '$1=="create_voucher_order" {print $6}')
  lag=${lag:-0}
  [ "$lag" = "0" ] && break
  sleep 2
done

# 2. 清订单相关表 + 重置库存
docker exec -i mysql mysql -uroot -proot 2>/dev/null <<SQL
TRUNCATE hmdp_0.tb_voucher_order_0; TRUNCATE hmdp_0.tb_voucher_order_1;
TRUNCATE hmdp_1.tb_voucher_order_0; TRUNCATE hmdp_1.tb_voucher_order_1;
TRUNCATE hmdp_0.tb_voucher_reconcile_log_0; TRUNCATE hmdp_0.tb_voucher_reconcile_log_1;
TRUNCATE hmdp_1.tb_voucher_reconcile_log_0; TRUNCATE hmdp_1.tb_voucher_reconcile_log_1;
TRUNCATE hmdp_0.tb_rollback_failure_log;
UPDATE hmdp_1.tb_seckill_voucher_0 SET stock=${STOCK}, init_stock=${STOCK} WHERE voucher_id=1;
SQL

# 3. 清 Redis 秒杀键（下次请求会重新加载库存）
redis-cli del "${PREFIX}-seckill:stock:{1}" "${PREFIX}-seckill:user:{1}" "${PREFIX}-seckill:trace:log:{1}" >/dev/null
echo "reset done, stock=${STOCK}"
