# 后端栈专项审查

识别栈后只读对应章节；多栈 monorepo 分段审查。若是未知语言或小工具项目，至少执行「通用后端模式」和「CLI / 脚本」两节。

## Python（FastAPI / Django / Flask）

**规范原文**: [../code-security/08.Python安全.md](../code-security/08.Python安全.md)

### 语言级危险面

| 检查项 | 搜索/位置 |
|--------|-----------|
| eval/exec/compile | `bandit` B102/B201；rg `eval\(|exec\(` |
| pickle 反序列化 | `pickle.loads`, `yaml.load(` 无 SafeLoader |
| subprocess shell=True | B602/B604 |
| SSTI | Jinja2 无 `autoescape` |
| 路径穿越 | 用户输入拼 `open()`/`Path` |
| 密钥 | `.env` 进 git；`ai_read/*KEYS*` 明文 |

### FastAPI / 异步 SaaS 常见模式（融合审计）

| 模式 | 审查点 |
|------|--------|
| 鉴权 | 路由缺 `Depends(get_current_user)`；带 `projectId` 缺 `require_project_access` |
| 错误 | 裸 `HTTPException(detail=...)` 泄露栈；应 `fail(ErrorCode.*)` |
| 算力 | 须走 `submit_node_generation` → `reserve_for_job`；禁止路由内改 `compute_power` |
| Redis 锁 | `redis_mutex` fail-closed；`auth_volatile` 内存兜底 **仅 dev** |
| 退款 | `credit_refund_lock` 按 jobId；上游 in-flight 默认 skip |
| Worker | `SKIP LOCKED` 抢单 + `worker_claim_id`；stale/reconcile |
| 存储 | `CanvasOssStorage.put`；生产 `CANVAS_STORAGE_LOCAL_ONLY=false` |
| 密钥 | 仅 `llm_keys.py` / `llm-keys.env`；前端只传 model |
| 时间 | `datetime_util` 东八区；trace 与 API 同时区 |

**并发资损反模式**：

```python
# 反模式
user.balance -= cost
await db.commit()

# 期望：generation_submit_lock → reserve_local_credits → FOR UPDATE lots
```

## Java（Spring Boot / MyBatis）

| 检查项 | 搜索/位置 |
|--------|-----------|
| SQL 注入 | `${}` in MyBatis XML |
| 鉴权 | `@PreAuthorize` 缺失；`permitAll()` 过宽 |
| 事务 | `@Transactional` self-invocation 失效；**长事务内 HTTP** |
| 锁顺序 | 先 Redis 锁再 `@Transactional`（见 AI 标准 §9） |
| 并发 | 余额无 FOR UPDATE；秒杀无 Redis 锁+DB 双保 |

**Spring Security 快速点**：

- CSRF：纯 API 可关，浏览器 cookie 会话不可关
- CORS：非 `*` + credentials
- Actuator `/actuator/**` 须鉴权或内网

## Go

| 检查项 | 搜索/位置 |
|--------|-----------|
| SQL 注入 | `fmt.Sprintf` 拼 SQL |
| 路径穿越 | `http.Dir` + 用户路径 |
| TLS | `InsecureSkipVerify: true` |
| 竞态 | shared map 无 mutex；balance 无事务 |
| 错误泄露 | `err.Error()` 直接写响应 |
| SSRF | `http.Get(userURL)` 无白名单 |

## Node.js（Express / Nest / Koa）

| 检查项 | 搜索/位置 |
|--------|-----------|
| 原型污染 | `lodash.merge` 旧版；不可信对象 deep merge |
| NoSQL 注入 | `{ $gt: "" }` 进 Mongo 查询 |
| XSS 存储 | 服务端渲染未 escape |
| 鉴权 | middleware 顺序错误；部分路由未挂载 |
| 依赖 | `npm audit`；`node-serialize` 等历史 RCE |
| 文件上传 | `multer` 仅 extension 校验 |

## .NET（ASP.NET Core / MVC / Worker）

| 检查项 | 搜索/位置 |
|--------|-----------|
| 鉴权 | `[AllowAnonymous]` 过宽；Controller/Minimal API 缺 `[Authorize]` |
| 授权 | 只验登录不验 tenant/user 归属；Policy/Role 名称不一致 |
| SQL 注入 | `FromSqlRaw`/字符串拼接 SQL；Dapper 拼接 |
| Mass assignment | DTO 直接映射 Entity，敏感字段可被覆盖 |
| CSRF | Cookie 会话 MVC 未启用 Antiforgery |
| SSRF | `HttpClient.GetAsync(userUrl)` 无 allowlist |
| 反序列化 | `BinaryFormatter`、不可信 JSON TypeNameHandling |
| 密钥 | `appsettings*.json`、UserSecrets、连接串进仓库 |

**ASP.NET Core 快速点**：

- CORS：`AllowAnyOrigin` + credentials 禁止
- Swagger：生产环境需鉴权或关闭
- Kestrel/反代：真实 IP、HTTPS redirect、HSTS 配置
- BackgroundService：异常不应静默退出；任务幂等 + 事务边界

## PHP（Laravel / ThinkPHP / Symfony）

| 检查项 | 搜索/位置 |
|--------|-----------|
| SQL 注入 | `DB::raw`、拼接 whereRaw、原生 SQL 变量 |
| Mass assignment | Laravel `$guarded = []`；缺 `$fillable` |
| 鉴权 | route middleware 缺 `auth` / policy / gate |
| CSRF | Web 路由关闭 VerifyCsrfToken |
| 文件上传 | 只校验扩展名；上传目录可执行 PHP |
| 命令执行 | `shell_exec`, `exec`, `passthru`, `system` |
| 反序列化 | `unserialize($_*)` |
| 密钥 | `.env`、`APP_KEY`、数据库密码进仓库 |

**Laravel 快速点**：

- 管理后台路由必须挂 `auth` + 权限中间件
- API Token/Passport/Sanctum 能区分用户端与管理端
- `APP_DEBUG=false`；异常页不暴露 SQL/路径
- Queue job 幂等；外部回调验签 + UNIQUE

## 通用后端模式（任意语言）

### 中间件应集中而非散落

期望：认证、限流、RequestId、统一异常（稳定 code）、审计——见 [architecture-patterns.md](architecture-patterns.md)。

**分层边界**（Java 单体常见）：Controller 仅校验+调用；Service 事务+锁编排；禁止 Controller 直写 Redis/HTTP。

### Webhook / 回调

- [ ] 独立路径；验签
- [ ] 幂等表或唯一键
- [ ] IP  allowlist（若渠道支持）

### 配置与密钥

- [ ] 12-factor：环境变量 / 密钥管理服务
- [ ] 区分 dev/prod；prod 无 mock 认证
- [ ] 数据库 URL、OSS key 不进日志

### 错误码设计

- [ ] 稳定 `code` 字段供前端分支（非仅 HTTP status + 中文 message）
- [ ] 402/409/429 语义正确（余额不足/冲突/限流）

## CLI / 脚本 / 批处理

适用 Bash、Python 脚本、Node CLI、Go/Rust 小工具、数据迁移脚本、CI 辅助程序。

| 检查项 | 风险 | 期望 |
|--------|------|------|
| 命令执行 | 参数注入 | 参数数组调用；必要时 allowlist |
| 文件路径 | 路径穿越/覆盖系统文件 | `realpath` 后限制在工作目录 |
| 临时文件 | 竞争/泄露 | 安全临时目录；权限 0600 |
| 凭证 | 打印到日志/CI | mask；不 echo secret |
| 删除/迁移 | 误删生产 | dry-run、确认环境、最小范围 |
| 网络请求 | SSRF/下载恶意文件 | URL allowlist、校验 hash/签名 |
| 依赖安装 | 供应链 | lockfile、固定版本、校验源 |

脚本类 finding 要说明触发命令和输入样例；没有可利用输入时降级为加固建议。
