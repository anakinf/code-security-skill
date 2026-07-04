# 架构级安全、边界与性能模式

跨项目审计透镜；与 [ai-code-standard-skill/cross-cutting-constraints.md](../ai-code-standard-skill/cross-cutting-constraints.md) **同构**。不含具体业务规则。

---

## 1. 系统边界

| 边界 | 审查问题 | 典型违规 |
|------|----------|----------|
| 权威源 | 状态/计数以谁为准 | Redis/localStorage 当唯一结果 |
| 存储分工 | 结构化 vs 大对象 vs 缓存 | 热表存 BLOB；OSS 无索引 |
| 租户 | 资源是否绑定 tenant/project | 只验登录不验归属 |
| 密钥 | 从哪加载 | 进前端、进 git |

---

## 2. 基础设施：锁 · 缓存 · MQ · 网关

与 cross-cutting §2 一致；审计时按下列逐项找证据。

### 2.1 组件分工

```
DB  = 真相 + UNIQUE 幂等
Redis = 查询缓存 | 锁/占位/限流（可重建）
MQ  = 持久异步 + 写前日志（不可替代为 Redis List）
```

### 2.2 Redis 锁 A–E + D+（TTL 1s～7d）

| 类 | 目的 | TTL | 审计 grep |
|----|------|-----|-----------|
| **A 并发互斥** | 同时写同一资源 | 1～30s | `lock:` + `finally`/`DEL` |
| **B 防连点** | 双 POST | 2～10s | Idempotency-Key |
| **C 在途** | 处理中重复触发 | 1～30min | 终态删 key |
| **D 防重复副作用** | 回调、补偿、外部 POST | 1h～1d | `done:` + UNIQUE |
| **D+ 长窗口** | 迟达回调、对账周期、不可逆审核 | **1d～7d** | 同 D；须 SLA |
| **E 调度** | 多 Worker 重复消费 | 秒 + DB | Lua/ZSET、`SKIP LOCKED` |

**必问**：A / D / D+？TTL 依据？>1d 为何需要？TTL 过期后 DB UNIQUE 能否拒双做？

生产 TTL spread 样例：[reference-java-monolith-redis.md](../ai-code-standard-skill/distill/reference-java-monolith-redis.md) §3。

### 2.3 三层 + 写顺序

```
L1 Redis（A/D/D+）→ L2 FOR UPDATE → L3 UNIQUE
本地成功 → 再外部 HTTP → 再 200
先 claim 流水 → 再增计数
finalize_failure → compensate 网关 → 终态 → 写穿缓存
禁止：事务内 HTTP/OSS | 内存锁替代 Redis（副作用路径）
```

### 2.4 Fail-closed 矩阵

| 路径 | Redis down | 锁占用 |
|------|------------|--------|
| 副作用/风控 | **503** | 429/409 |
| D 已占位 | — | 幂等成功 |
| 纯查询缓存 | 降级 DB | — |
| 限流 | 可标记缺口 | 429 |

### 2.5 副作用网关（单一入口）

| 禁止 | 要求 |
|------|------|
| 多文件直调 `compensate_*` / 直改汇总字段 | 每类副作用一个 gateway |
| 失败路径各自补偿 | 唯一 `finalize_failure(entity, reason)` |
| Controller 内 DEL cache | 网关内 DB commit 后写穿 |

验收：`rg 'compensate_|release_' --glob '!**/gateways/**'` 无散落（路径按项目约定）。

### 2.6 Redis 缓存

- 查询 key：分钟 TTL + 随机偏移；穿透/击穿/雪崩
- 控制 key（受理、D 占位、A 锁）：**独立 TTL**
- 命中仍鉴权
- 改库走统一入口更新 cache

### 2.7 MQ 与 DB Job

- MQ：持久 + confirm；消费幂等 + D/D+ + UNIQUE
- **无 MQ**：DB 任务行 + 调度器（同幂等/对账要求）；禁止 Redis List 唯一队列
- 参考：[reference-java-monolith-redis.md](../ai-code-standard-skill/distill/reference-java-monolith-redis.md) §7

---

## 3. 稀缺资源预占（有则查，无则 N/A）

有「扣完即没」的计数/配额时：

| 检查 | 要求 |
|------|------|
| 模型 | reserve → commit / release，非单字段 UPDATE |
| 失败 | release 原路；中间态有 reconcile |
| 幂等 | `{domain}-{entityId}`；重复 reserve 不重复扣 |
| 网关 | reserve / compensate 各单一入口 |

普通 CRUD **跳过**本节。

---

## 4. 异步 API + Worker（有则查）

| 角色 | 允许 | 禁止 |
|------|------|------|
| API | 鉴权、限流、幂等、Redis 快照、发 MQ | 峰值同步写大表 + 外部 POST |
| Worker | 幂等消费 → 事务入库+占用 → 再外部 | 占用失败仍调外部 |
| Poll/调度 | 批量、限流、E 类互斥 | 无上限打外部；未核实即补偿 |

**对账**

| 故障 | 兜底 |
|------|------|
| 已 confirm 无 DB 行 | 重入队 |
| MQ 重复 | 消费幂等 + UNIQUE |
| Redis 调度丢失 | DB `status + next_run_at` 重建 |
| 非终态卡住 | 超时 finalize（先补查外部） |

---

## 5. 其余（简要）

**API 错误**：稳定 `code`；不返栈/SQL。

**OSS**：私有 + HTTPS 签名；sign-url 验归属；revision 409。

**密钥**：集中加载；扫 git 泄露。

**外部 HTTP**：timeout、限流、POST 幂等 key；非幂等慎重重试。

**SQL**：参数化；无事务内长 I/O；无 N+1。

---

## 6. 审计 grep 包

```
redis_mutex|SETNX|FOR UPDATE|idempotency|dedupe_key
done:|lock:|publisher.confirm|accepted:
compensate_|finalize_failure|只改库
fail-open|in-memory.*Lock
HTTPException\(detail|traceback
```

---

## 7. 外部文档（提取模式，不复制业务）

| 文档 | 提取 |
|------|------|
| [code-security/06.Redis安全.md](../code-security/06.Redis安全.md) | 缓存一致性 |
| [code-security/15.上线Checklist.md](../code-security/15.上线Checklist.md) | 缓存/MQ 验收 |
| [聚梦画布-生成任务性能改造方案.md](../code-security/聚梦画布-生成任务性能改造方案.md) | Submit/Poll/MQ/对账**模式** |
| `AI_RULE.md` §7–9 | 事务、缓存、锁顺序 |
