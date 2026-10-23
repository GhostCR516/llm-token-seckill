#!/bin/zsh
# 第三组测试：秒杀正确性验证
# 用法: verify_seckill.sh <初始库存>
# PREFIX 需与后端 -Dprefix.distinction.name 保持一致
INIT_STOCK=${1:-100}
PREFIX=${PREFIX:-ghost}
docker exec -i mysql mysql -uroot -proot 2>/dev/null <<SQL
SELECT ${INIT_STOCK} AS init_stock;
SELECT stock AS mysql_stock_after FROM hmdp_1.tb_seckill_voucher_0 WHERE voucher_id=1;
SELECT (SELECT COUNT(*) FROM hmdp_0.tb_voucher_order_0)+(SELECT COUNT(*) FROM hmdp_0.tb_voucher_order_1)
     +(SELECT COUNT(*) FROM hmdp_1.tb_voucher_order_0)+(SELECT COUNT(*) FROM hmdp_1.tb_voucher_order_1) AS total_orders;
SELECT COUNT(*) AS dup_users FROM (
  SELECT user_id FROM (
    SELECT user_id FROM hmdp_0.tb_voucher_order_0 UNION ALL
    SELECT user_id FROM hmdp_0.tb_voucher_order_1 UNION ALL
    SELECT user_id FROM hmdp_1.tb_voucher_order_0 UNION ALL
    SELECT user_id FROM hmdp_1.tb_voucher_order_1
  ) t GROUP BY user_id HAVING COUNT(*) > 1
) d;
SELECT (SELECT COUNT(*) FROM hmdp_0.tb_voucher_reconcile_log_0)+(SELECT COUNT(*) FROM hmdp_0.tb_voucher_reconcile_log_1)
     +(SELECT COUNT(*) FROM hmdp_1.tb_voucher_reconcile_log_0)+(SELECT COUNT(*) FROM hmdp_1.tb_voucher_reconcile_log_1) AS reconcile_logs;
SELECT COUNT(*) AS rollback_failures FROM hmdp_0.tb_rollback_failure_log;
SQL
echo "---- redis ----"
redis-cli get "${PREFIX}-seckill:stock:{1}"
redis-cli scard "${PREFIX}-seckill:user:{1}"
echo "---- kafka lag ----"
docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group create_voucher_order 2>/dev/null | awk '$1=="create_voucher_order" {print "lag="$6}'
