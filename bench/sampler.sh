#!/bin/zsh
# 资源采样：每 5 秒记录 docker stats + MySQL 状态 + Redis 命中统计
OUT="$(cd "$(dirname "$0")" && pwd)/results/sampler.log"
while true; do
  ts=$(date '+%H:%M:%S')
  stats=$(docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' 2>/dev/null | tr '\n' ';')
  mysql_stats=$(docker exec mysql mysql -uroot -proot -N -e "SHOW GLOBAL STATUS LIKE 'Threads_connected'; SHOW GLOBAL STATUS LIKE 'Questions';" 2>/dev/null | tr '\n\t' '  ')
  redis_stats=$(redis-cli info stats 2>/dev/null | grep -E '^(keyspace_hits|keyspace_misses)' | tr -d '\r' | tr '\n' ' ')
  echo "$ts | $stats | $mysql_stats | $redis_stats" >> $OUT
  sleep 5
done
