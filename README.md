# 算力商城 · 大模型 Token 包秒杀系统

面向大模型 API 聚合平台的高并发交易实战项目：平台聚合多家模型服务商（OpenAI / Anthropic / 国产大模型等），以**限量秒杀**的形式发售折扣 Token 算力包。围绕「高并发下的 Token 包秒杀」与「热点服务商查询」两个真实问题，提供端到端的稳定性与一致性解决方案，并附带**完整可复现的压测数据**。

技术栈：SpringBoot 3 / MyBatis-Plus / Redis（Redisson）/ Kafka / ShardingSphere 分库分表 / Caffeine 多级缓存 / Vue3。

## 业务场景映射

| 业务概念 | 系统中对应 |
|---|---|
| 模型服务商（OpenAI、文心等） | 服务商（shop）浏览、检索、详情 |
| Token 算力包（如 100M tokens 折扣包） | 普通券 / 秒杀券（voucher） |
| Token 包秒杀订单 | 秒杀订单（voucher_order，分库分表） |
| 开发者测评 / 种草 | 达人笔记（blog）、点赞排行榜 |
| 补货提醒 | 售罄订阅通知 |

## 性能实测（k6 压测，单机单实例）

完整数据、口径说明与复现脚本见 [docs/压测报告.md](docs/压测报告.md)。

- 秒杀核心链路（双层限流 → 一次性令牌 → Lua 原子预扣 → Kafka 异步落库）稳定承载 **≈1500 QPS**（约 2900 HTTP req/s），50→400 并发全程 **0% 错误率**，200 并发内 P50 ≤ 9ms。
- 热点查询经「Caffeine 本地缓存 + Redis + 布隆过滤器 + 空值缓存 + 双重检测锁」优化后：QPS **4,136 → 15,246（3.7×）**，平均延迟 **4.8ms → 1.28ms**，**MySQL 读流量降低 99.98%**（248,219 → 57 次/分钟）。
- 正确性：300 用户并发抢 100 份库存，最终 **恰好 100 笔订单、0 超卖、0 重复下单、Redis/MySQL 库存对平**；同一用户 2.9 万次并发请求仅产生 1 笔订单（一人一单）。
- 多级缓存失效经 Kafka 广播，跨实例传播延迟 **<200ms**；消费端 10s 延迟丢弃 + 库存回滚 + 对账日志兜底链路在压测中验证生效。
- 压测过程中发现并修复了上游项目一个真实 bug（更新接口重复 `update()` 生成无 SET 的非法 SQL，命中率 100%），见[压测报告第六节](docs/压测报告.md)。

## 核心问题与方案

### 1. 秒杀链路一致性闭环

```
HTTP → IP/用户双层限流 → 秒杀令牌校验(一次性) → Redis Lua 原子预扣库存 + 一人一单(SISMEMBER)
     → Kafka 异步下单 → 消费端幂等 + 10s 延迟丢弃 → ShardingSphere 分库分表落库(2库×2表)
     → 对账日志 / 失败回滚 Redis 库存
```

- **超卖防护**：库存预扣与一人一单校验在单条 Lua 脚本内原子完成。
- **消息可靠性**：生产端确认 + 指数退避重试；消费端幂等去重；超时消息丢弃并自动回滚库存，回滚失败落兜底表。
- **对账**：订单对账日志与扣减流水周期性比对，差异进入补偿流程。

### 2. 热点查询缓存体系

- **防穿透**：布隆过滤器拦截非法 ID + 空值短 TTL 缓存。
- **防击穿**：本地缓存（Caffeine）+ Redis 双层缓存、双重检测锁（DCL）重建、逻辑过期 + 异步重建。
- **失效一致性**：更新经 Kafka 广播，所有实例的 L1/L2 缓存在 200ms 内失效并回源。

### 3. 入口流量治理

- **令牌前置授权**：抢购前先申请一次性资格令牌，未持有令牌不进入扣减链路。
- **分布式令牌桶**：按 IP / 用户双维度限流，支持白名单与动态阈值。

### 4. 数据层扩展

- 订单、对账日志等热点表按 ShardingSphere 分库分表（2 库 × 2 表）。
- 自研全局 ID 生成器，保障跨分片唯一与有序。

### 5. 其他组件化能力

- 重构的 Redisson 分布式锁组件：读锁/写锁/公平锁，注解式、命令式、方法级多种接入。
- 分布式幂等组件：注解式防重复提交 / 防重复消费。
- 分片化延迟队列（Redisson 重构）：开抢前预通知、订单超时关闭、补货触达。
- SortedSet 每日 Top 买家榜、ZSet 售罄订阅通知。

## 快速启动

中间件依赖：MySQL 8、Redis、Kafka（KRaft）。

```bash
# 1. 导入数据库（sql/ 目录，两个分片库 hmdp_0 / hmdp_1）
mysql -uroot -proot --default-character-set=utf8mb4 < sql/hmdp.sql

# 2. 启动后端（JDK 17；MySQL/Kafka/Redis 地址见 hmdp-core-service/src/main/resources/application.yml）
mvn -q package -DskipTests
java -jar hmdp-core-service/target/hmdp-core-service-0.0.1-SNAPSHOT.jar

# 3. 启动前端
cd hmdp-vue3 && npm install && npm run dev
```

可选启动参数：`-Dprefix.distinction.name=<name>` 为 Redis key 与 Kafka topic 加隔离前缀；`-Drate-limit.ip-whitelist=<ip>` 配置限流白名单。

## 压测复现

```bash
python3 bench/gen_tokens.py        # 生成 2000 个压测用户 token
bench/run_matrix.sh                # 秒杀性能矩阵（50/100/200/400 并发 × 3 轮）
bench/reset_seckill.sh 100         # 重置库存为 100
VUS=300 DURATION=30s k6 run bench/seckill.js   # 超卖验证
bench/verify_seckill.sh 100        # 正确性校验（订单数/库存对平/Kafka lag）
```

## 致谢与许可

本项目基于 [hmdp-plus](https://github.com/java-up-up/hmdp-plus)（Apache License 2.0）二次开发，在原项目「黑马点评 Plus」的高并发架构基础上，将业务场景重构为大模型平台 Token 包秒杀，并补充了完整的性能压测与正确性验证体系。原始许可证见 [LICENSE](LICENSE)。
