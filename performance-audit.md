# 性能与可靠性审计

与安全交叉项（并发资损、缓存一致性、异步边界）一并报告。架构模式详见 [architecture-patterns.md](architecture-patterns.md)。

## 0. 先识别架构阶段

| 形态 | 性能焦点 | 安全/资损焦点 |
|------|----------|---------------|
| 同步 monolithic Worker | 长占槽、单协程 sleep poll | 预扣在 API/Worker 同步路径 |
| API + MQ + Submit/Poll | 写抗峰、Poll 批量 | confirm 前返回、双轨双消费 |
| 混合灰度 | 路由清晰、drain 旧任务 | 同 jobId 不双处理 |

**不要求**未上线的 MQ 阶段强行通过；在报告中标注「改造后项」。

## 1. 数据库

| 模式 | 识别 | 风险 |
|------|------|------|
| N+1 查询 | 循环内 query；前端 per-node asset fetch | 延迟、连接耗尽 |
| 无分页全表 | 管理端导出无时间窗 | 与 Worker 抢单/Poll 争 IO |
| 缺索引 | `status+next_poll_at`、`lane+status` 等 | 闹钟/抢单扫表 |
| 长事务 | 事务内 HTTP/OSS/AI | 行锁、连接池耗尽 |
| 大字段热路径 | 列表带 flow_json/BLOB | buffer、带宽 |
| API 同步写重表 | 峰值 INSERT generation_jobs | 提交失败、连接池打满 |

**审查动作**：

- 列表/导出 → `limit`/cursor + **时间范围**
- Worker/Poll → 只扫「进行中」状态，不扫历史
- `FOR UPDATE` 范围 → 锁粒度（按 user/lot 而非全表）

## 2. 缓存（Redis / 本地）

| 模式 | 风险 | 期望 |
|------|------|------|
| 只改库不更 Redis | 脏读 | 写穿统一入口 |
| 状态缓存 TTL 套用在受理凭证 | 误判 404/失败 | `job:accepted` TTL = MQ 堆积 SLA |
| 缓存命中跳过鉴权 | 越权读 job 状态 | 先 auth 再读 Redis |
| 热点 key 单点 | Redis 瓶颈 | 分散 / 本地短缓存 |
| 缓存作扣费依据 | 资损 | DB lot 为准 |
| 击穿无互斥 | 惊群打 DB | SETNX 重建 |
| 雪崩无随机 TTL | 同时过期 | base + random offset |

**Fail-open 缺口**（须标注）：`check_rate_limit` Redis down 放行——与资损路径 fail-closed 对比。

## 3. 异步 Submit / Poll / MQ

### 3.1 提交链性能+安全

```
API(ms级): 鉴权 → quote校验 → SETNX dedupe → Redis pending → MQ confirm → 返回 jobId
Submit(s级): 幂等消费 → 事务(写库+预扣) → POST上游 → 写 ZSET 闹钟
```

| 检查 | 违规后果 |
|------|----------|
| API 不写大表 | 峰值写爆 MySQL |
| confirm 后返回 | 丢消息却给 jobId |
| 报价快照进 MQ | Worker 排队后改价资损 |
| Idempotency-Key 强制 | 多 uvicorn 重复任务 |

### 3.2 Poll 链

| 检查 | 要点 |
|------|------|
| ZSET 批量 ZRANGEBYSCORE | 非 per-job sleep 协程 |
| Lua 原子取删 | 多 Poll Worker 不重复 |
| 全局限流（按上游 Provider） | 防 429、合同配额 |
| 下载池有上限 | 内存尖峰（无 swap 环境） |
| 超时先补查上游 | 误 release 资损 |
| `downloading` 卡住 | 对账重新收尾（幂等） |

### 3.3 对账与兜底

| 故障 | 兜底 |
|------|------|
| MQ 确认但 DB 无行 | 扫 `job:accepted` 重新入队 |
| Redis ZSET 丢失 | DB `next_poll_at` 重建 |
| Poll 崩溃 mid-download | `downloading` 超时对账 |
| commit/release 中间态 | reconcile loop |

### 3.4 双轨灰度

- 新任务走路由/MQ；旧 pending 由旧 Worker drain
- **同一 jobId** 禁止旧 claim + MQ 双消费
- 回滚：关 feature flag，保留旧 Worker

## 4. Worker / 并发槽（monolithic 或混合）

| 模式 | 风险 |
|------|------|
| 单 job 占槽至 poll+下载结束 | 有效并发远低于槽位数 |
| model slot 租约与 job 生命周期不匹配 | 槽泄漏或过早释放 |
| `FOR UPDATE SKIP LOCKED` 抢单 | 多实例正确；无 SKIP 则串行 |
| worker_job_lock best-effort | Redis down 可能双执行——靠 claim token |

生产参数拆分：`JOB_TIMEOUT` 应对 Submit/Poll/Finalize 分段，非整条 monolithic。

## 5. 外部依赖

- [ ] HTTP：timeout + 重试策略（POST 非幂等谨慎）
- [ ] 上游 QPS 全局限流（多 Worker 共享桶）
- [ ] 连接池 ≈ worker 数 × 并发
- [ ] OSS：batch manifest / sign-url，禁 N+1
- [ ] 熔断：外部失败率阈值快速失败

## 6. API 层

- [ ] batch assets（如 ≤200 ids/次）替代 per-item
- [ ] gzip/brotli（Nginx）
- [ ] 乐观锁 revision → 409
- [ ] 生成状态对外映射，禁 raw internal enum

## 7. 前端

- [ ] manifest O(1) 预览，禁每节点重复拉同一 assetId
- [ ] 轮询间隔合理；禁 WebSocket 重连风暴
- [ ] in-flight disabled ≠ 永久禁生成
- [ ] Bundle / lazy load / 大 JSON Worker  offload

## 8. 可观测性（排障前提）

| 指标 | 用途 |
|------|------|
| MQ 深度 / 消费延迟 | Submit 堆积 |
| Redis ZSET 深度 / Poll loop lag | 轮询健康 |
| 上游 QPS / 429 率 | 限流配置 |
| `downloading` 卡住数 | 收尾失败 |
| `commit_pending` / `release_pending` | 算力对账 |
| Submit 异步余额不足率 | 402 变异步体验 |
| API P95 / Worker slot 占用 | 容量规划 |

## 报告格式

与安全问题相同，额外：

- **影响**: 延迟 / 吞吐 / 成本 / 稳定性 / 资损
- **触发条件**: QPS、数据规模、架构阶段
- **建议**: S/M/L；若涉及灰度，注明分期
