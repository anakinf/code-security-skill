# 使用示例

## 快速代码体检

用户：「帮我检查 `/work/app` 这个项目代码有没有安全问题」

Agent 流程：

1. 识别栈、入口类型、依赖文件、部署配置
2. 运行 `bash .../code-security-skill/scripts/scan.sh /work/app`
3. grep 危险 API、密钥、鉴权绕过、SQL/命令执行
4. 读路由/Controller/Service/Repository 或 CLI 主入口
5. 输出 Top 风险、自动扫描摘要、是否建议深挖

## 全库审计

用户：「帮我对这个项目做上线前安全检查」

Agent 流程：

1. 读 `SKILL.md` + **`architecture-patterns.md` §1** 填系统边界表
2. 运行 `bash .../code-security-skill/scripts/scan.sh .`
3. 搜索 architecture-patterns §11 审计搜索包
4. 对照 checklist-core + stack-backend
5. 输出 report-template（含边界摘要节）

## PR 增量审计

用户：「Review 这个 PR 的安全问题」

1. `git diff main...HEAD --name-only` 限定范围
2. 仅审查变更文件 + 受影响调用链
3. 报告注明「增量范围」

## Java 单体

用户：「审计 Spring Boot 后台」

1. stack-backend § Java
2. 查 MyBatis `${}`、`@PreAuthorize`、事务边界
3. checklist-infra 若含 Docker 部署

## 性能 + 安全联合

用户：「生成任务有没有资损和性能问题」

1. 读 `architecture-patterns.md` §3–4，识别 monolithic **或** Submit/Poll 阶段
2. 对照 `ai_read/canvas_locks_and_concurrency.md`（若存在）核对 fail-closed 矩阵
3. performance-audit §3 + checklist-core §3.1、§3.4

## 脚本 / CLI 项目

用户：「检查这个数据迁移脚本目录」

重点查：

- 参数是否进入 shell / SQL / 文件路径
- 是否有 dry-run、环境确认、备份和幂等
- 日志是否打印连接串、Token、PII
- 删除/覆盖操作是否限制在工作目录

## 架构级 Finding 示例（融合审查）

### 🔴 Critical — 明文密钥文档进仓库

- **位置**: `ai_read/MODELS_AND_API_KEYS.md`
- **问题**: 文档含 `sk-`/`LTAI` 等运行时密钥
- **风险**: git 泄露即上游/OSS 全量失守
- **修复**: 移出 git、rotate 密钥、改 example 模板；运行时仅 env/Secret Manager
- **规范**: architecture-patterns §8 / checklist-core §8

### 🔴 Critical — Redis 缓存命中跳过项目鉴权

- **位置**: `GET /generations/{jobId}` handler
- **问题**: Redis hit 直接返回，未 `require_project_access`
- **风险**: 猜 jobId 读他人任务状态/结果 URL
- **修复**: 鉴权在前，缓存其后
- **规范**: architecture-patterns §4.3

### 🟠 High — 限流 Redis 不可用仍放行

- **位置**: `services/cache.py` → `check_rate_limit`
- **问题**: Redis down 返回 True
- **风险**: 生成/上传接口可被刷（与算力 fail-closed 不一致）
- **修复**: 文档化为已知缺口或改为 fail-closed（按接口敏感度）
- **规范**: architecture-patterns §2.3

### P-1 — API 峰值同步 INSERT 任务大表

- **问题**: 提交路径在 API 进程写 `generation_jobs` + 预扣
- **影响**: 峰值连接池/索引锁竞争，提交 5xx
- **建议**: 按 architecture-patterns §4 拆 Redis+MQ+Submit（分期）
- **复杂度**: L

### 🔴 Critical — 协作者生成未校验 project membership

- **位置**: `api/v1/generations.py:create_job`
- **问题**: 仅 `get_current_user`，未调用 `require_project_access`
- **风险**: 任意登录用户向他人 projectId 提交生成，消耗 owner 算力
- **修复**: 在 handler 入口添加 `require_project_access(db, user, project_id)`
- **规范**: checklist-core §1.3

### 🟠 High — 余额扣减无行锁

- **位置**: `services/wallet.py:deduct`
- **问题**: read balance → subtract → commit，无 `FOR UPDATE`
- **风险**: 并发请求双扣或余额变负
- **修复**: `SELECT ... FOR UPDATE` 或使用已有 `reserve_local_credits`
- **规范**: checklist-core §3.1

### P-1 — 资产 manifest N+1

- **位置**: `components/NodePreview.tsx`
- **问题**: 每节点独立 `fetch(/assets/{id})`
- **影响**: 大画布 100+ 请求，首屏慢
- **修复**: 使用 batch manifest API
- **复杂度**: S

## 反例

- 只贴扫描工具输出，不读业务代码
- 发现 UI 隐藏按钮就认为权限安全
- 把 Redis down 全部判失败；不区分查询缓存和资损路径
- 没有文件路径/函数名的 finding
- 修复建议另起一套架构，不复用项目现有抽象
- 对未知栈直接说“不支持”；至少做依赖、密钥、危险 API、输入边界快速体检
- 没证据就写“存在 SQL 注入”；只能写待确认并说明需要的输入路径
