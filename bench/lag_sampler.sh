#!/bin/zsh
# 第四组测试：Kafka lag 高频采样（每 2 秒），输出到 lag.log
OUT="$(cd "$(dirname "$0")" && pwd)/results/lag.log"
> $OUT
while true; do
  ts=$(date '+%H:%M:%S')
  line=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group create_voucher_order 2>/dev/null | awk '$1=="create_voucher_order" {print "offset="$4" end="$5" lag="$6}')
  echo "$ts $line" >> $OUT
  sleep 2
done
