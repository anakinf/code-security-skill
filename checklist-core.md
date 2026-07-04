# 核心安全清单（跨语言）

审计时在代码中逐项验证；`[ ]` 表示须找证据，`N/A` 表示项目无此能力。非 Web 项目仍需检查输入边界、执行边界、密钥、依赖和发布配置。

**与开发 skill 同构**：[architecture-patterns.md §2](architecture-patterns.md) · [cross-cutting-constraints.md](../ai-code-standard-skill/cross-cutting-constraints.md)

## §1 认证与授权

### 1.1 认证

- [ ] 所有业务 API 默认需认证（白名单明确且最小）
- [ ] Secret/密钥 ≥ 256 位随机，不在仓库与前端
- [ ] Token/Session 有过期；登出立即失效
- [ ] 当前用户 ID **只从服务端会话解析**，不信任请求体 `userId`
- [ ] 生产环境禁用 debug 绕过、测试 backdoor
- [ ] 验证码/风控存 Redis；Redis 不可用 **503**（副作用路径 fail-closed）

### 1.2 授权

- [ ] 写操作校验资源所有权或角色
- [ ] 列表/查询按权限过滤
- [ ] 水平/垂直越权测试

### 1.3 多租户（若适用）

- [ ] tenant/project membership 校验
- [ ] 非成员统一错误码

## §2 API 安全

- [ ] 稳定 `code`；不返栈/SQL/内部状态枚举
- [ ] 入参校验；分页上限
- [ ] 幂等：Idempotency-Key / dedupe UNIQUE
- [ ] Mass assignment 白名单
- [ ] 文件/URL/命令参数有 allowlist 或 schema 校验
- [ ] 外部回调、Webhook、开放 API 有签名/时间戳/重放防护

## §3 副作用与并发（有则必查）

### 3.1 稀缺资源（计数/配额/占用）

- [ ] reserve → commit / release，非单字段 UPDATE
- [ ] 三层：Redis（A/D）→ 行锁 → UNIQUE
- [ ] 写顺序：本地成功 → 再外部 HTTP → 再 200
- [ ] compensate / release **单一网关**；grep 无散落
- [ ] 缓存计数仅预检，DB 权威

### 3.2 领取 / 库存

- [ ] UNIQUE 防重复；事务内扣减+记录

### 3.3 支付类（若适用）

- [ ] 回调验签 + 幂等；防重复副作用 D 类锁 + 流水 UNIQUE

### 3.4 异步 / MQ / 外部 HTTP

- [ ] entityId + dedupe UNIQUE
- [ ] MQ 持久 + confirm 后返回 async id
- [ ] Worker：占用成功 → 再 POST 外部
- [ ] 失败 **仅** `finalize_failure` → compensate 网关
- [ ] Redis 查询仍鉴权；E 类调度互斥
- [ ] 超时先补查外部再 finalize
- [ ] 锁 A–E / D+（1d～7d 须 SLA）见 architecture-patterns §2.2

## §4 数据库

- [ ] 参数化；dedupe/流水 UNIQUE
- [ ] 最小权限；备份

## §5 Redis

- [ ] A–D 类 key TTL 与查询缓存分开
- [ ] 写穿：网关/Repository 统一更新 cache
- [ ] 穿透/击穿/雪崩
- [ ] 副作用路径禁止内存锁替代 Redis

## §6 存储

- [ ] 私有 OSS + HTTPS 签名；归属校验
- [ ] revision 409
- [ ] 本地文件读写限制在业务目录；防路径穿越
- [ ] 上传文件校验 MIME、大小、扩展名、内容；上传目录不可执行

## §7 日志

- [ ] 审计；脱敏；TraceId

## §8 密钥

- [ ] 集中加载；git 扫描

## §9 命令执行 / 反序列化 / 模板

- [ ] 禁止不可信输入进入 `eval/exec/new Function`
- [ ] Shell/Process 调用使用参数数组；无用户可控命令片段
- [ ] 反序列化只接受可信格式；禁用危险类型解析
- [ ] 模板/Markdown/富文本输出有 sanitize/escape
- [ ] SSRF：用户可控 URL 需 allowlist、内网 IP 拦截、超时

## §10 供应链 / 发布

- [ ] lockfile 存在且与包管理器一致
- [ ] 依赖扫描 HIGH/CRITICAL 已 triage
- [ ] CI 不打印 secret；产物不含 `.env`、source map、测试账号
- [ ] Docker/部署配置生产关闭 debug/mock/backdoor
