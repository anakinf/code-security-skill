---
name: code-security-audit
description: >-
  Perform structured security, reliability, and performance audits on codebases
  across backend, frontend, full-stack, monorepo, API service, admin system,
  SaaS, mobile/API-backed, CLI, and infrastructure repositories. Covers Python,
  Java, Go, Node.js, .NET, PHP, React, Vue, and similar stacks. Use when the user
  asks for code security review, vulnerability analysis, OWASP checks, IDOR or
  authorization review, business-risk or financial-loss review, dependency and
  secret scanning, pre-release checklist, performance risk review, CI security
  gate design, or mentions code-security / 安全审计 / 代码体检 / 上线验收.
---

# Code Security & Performance Audit

基于 [code-security 规范手册](../code-security/README.md) 的通用审计技能。**核心审查模型**见 [architecture-patterns.md](architecture-patterns.md)（系统边界、三层并发防护、**资源预占**闭环、Submit/Poll 异步边界、缓存一致性、fail-closed 矩阵）——**不含具体业务域**（算力/积分/生成任务等仅在项目本身涉及时才查对应章节）。

适用于任意代码项目：先画系统边界，再识别技术栈和运行入口，按分层清单审查，最后输出分级报告。Web 项目查认证授权和 API；脚本/CLI 查输入、文件、命令执行和密钥；移动/桌面项目重点查本地存储、API 鉴权和发布配置；基础设施仓库重点查网络暴露、密钥和最小权限。

## 何时使用

- 新项目/PR 安全评审、上线前验收
- 存量项目漏洞排查、资损/越权/并发问题定位
- 性能瓶颈与架构风险（N+1、缓存、队列、长事务）联合审查
- CI 门禁设计或补充自动化扫描
- 任意语言项目的快速代码体检、依赖/密钥扫描、危险 API 搜索
- 用户只给目录或说「帮我检查这个项目代码」时，默认做快速体检；若发现高风险域，再进入深度审计

## 审计模式

| 模式 | 适用 | 输出 |
|------|------|------|
| 快速体检 | 用户只给项目路径、时间有限、未知栈 | 项目画像 + 自动扫描摘要 + Top 风险 |
| PR/增量审查 | 有 diff、改动范围明确 | 只查变更触达链路；注明未覆盖旧代码 |
| 上线前深度审计 | 发布前、支付/余额/多租户/AI/OSS | 完整报告 + 阻塞项 + 修复优先级 |
| 专项审查 | 用户指定 Redis/MQ/权限/性能/密钥 | 只读相关清单，但仍先确认系统边界 |

用户未指定模式时：先做**快速体检**，发现 Critical/High 或敏感域后继续深挖相关调用链。

## 审计流程

复制并跟踪进度：

```
审计进度：
- [ ] 1. 项目画像（栈、边界、敏感域）
- [ ] 2. 自动化扫描（能跑则跑）
- [ ] 3. 后端安全审查
- [ ] 4. 前端安全审查
- [ ] 5. 业务/数据层审查（支付、余额、AI、协同）
- [ ] 6. 基础设施审查（DB/Redis/OSS/部署）
- [ ] 7. 性能与可靠性审查
- [ ] 8. 输出报告 + 修复优先级
```

### Step 1：项目画像 + 系统边界

**先读** [architecture-patterns.md §1](architecture-patterns.md#1-系统边界先画圈再查代码)，填写：

| 边界项 | 记录 |
|--------|------|
| 权威结构化存储 | MySQL / PG / … |
| 大对象存储 | OSS / S3 / 本地（生产是否禁止回退） |
| Redis 角色 | 仅锁/限流/SMS **或** 含读缓存（是否权威） |
| 租户隔离键 | projectId / tenantId / orgId / 无 |
| 账本/预扣 | 有 lot+reservation **或** 单 balance 字段 |
| 异步任务形态 | 同步 Worker / MQ+Submit+Poll / 混合灰度 |
| 密钥加载入口 | 单文件 / env / 分散（扫 git 泄露） |

再识别技术栈：

| 项 | 如何识别 |
|----|----------|
| 后端语言/框架 | `requirements.txt` / `pom.xml` / `go.mod` / `package.json` |
| 前端框架 | `package.json` dependencies、目录结构 |
| 认证方案 | JWT / Session / HMAC / OAuth 实现文件 |
| 部署形态 | Docker/systemd/K8s/Nginx |
| 入口类型 | Web/API/Worker/CLI/移动端/桌面/infra-only |

**项目级规则优先**：`.cursor/rules/`、`ai_read/*lock*`、`AI_RULE.md`（仅 §7–9、§12–13、§15、§17 安全/性能条款）、内部架构 doc——提取**边界与写顺序**，不照搬业务描述。

### Step 1.5：范围裁剪

先列出审计范围，避免报告看似全面但证据不足：

- **全量仓库**：读取依赖、入口、路由、认证、数据层、部署配置
- **指定模块**：沿入口向下追 controller/service/repository/job，不只看单文件
- **PR diff**：审查变更文件 + 被调用安全边界；老问题只在影响新链路时列入
- **无法运行工具**：说明缺失工具/依赖，人工 grep 和代码阅读继续进行

### Step 2：自动化扫描

按栈执行（详见 [automation.md](automation.md)）：

```bash
# 在项目根目录，按检测结果选择性运行
bash /path/to/code-security-skill/scripts/scan.sh .
```

或手动：

- Python: `bandit -r . -ll`, `pip-audit`, `semgrep --config=registry/owasp-top-ten`
- Node: `npm audit --audit-level=high`
- Java: `mvn org.owasp:dependency-check-maven:check`（若已配置）
- 容器: `trivy fs .`
- .NET: `dotnet list package --vulnerable --include-transitive`
- PHP: `composer audit`

扫描结果**不能替代**人工审查（业务越权、并发资损、架构缺陷需读代码）。

### Step 3–6：分层人工审查

按域对照清单，**每条发现须附文件路径与行号/函数名**：

| 域 | 清单文件 |
|----|----------|
| 认证授权、RBAC、越权 | [checklist-core.md](checklist-core.md) §1 |
| API、限流、幂等、错误泄露 | [checklist-core.md](checklist-core.md) §2 |
| 余额/订单/AI/协同资损 | [checklist-core.md](checklist-core.md) §3 |
| 后端语言专项 | [stack-backend.md](stack-backend.md) |
| 前端专项 | [stack-frontend.md](stack-frontend.md) |
| DB / Redis / 文件 / OSS | [checklist-core.md](checklist-core.md) §4–6 |
| 部署 / Nginx / Docker | [checklist-infra.md](checklist-infra.md) |
| CLI/脚本/批处理 | [stack-backend.md](stack-backend.md) 通用后端模式 + 命令/文件输入 |

**代码搜索模式**（按语言调整）：

```
# 高危函数
eval|exec|pickle\.loads|yaml\.load|shell=True|innerHTML|dangerouslySetInnerHTML

# 鉴权绕过
@Public|permitAll|skipAuth|ADMIN_AUTH_DISABLED|without.*auth

# SQL 风险
execute\(.*\+|f".*SELECT|rawQuery.*\+

# 密钥泄露
password\s*=|api_key\s*=|secret\s*=|AKIA[0-9A-Z]{16}

# 并发/资损（见 architecture-patterns §2–3）
FOR UPDATE|idempotency|dedupe|reserve_for|release_for|redis_mutex|SET NX

# 异步边界（见 architecture-patterns §4）
Idempotency-Key|quoteToken|publisher.confirm|job:accepted|dedupe_key

# fail-closed / 降级
_volatile_store|in-memory|fail-open|ADMIN_AUTH_DISABLED|CANVAS_STORAGE_LOCAL_ONLY

# CLI / 文件处理
subprocess|ProcessBuilder|exec.Command|System.Diagnostics.Process|shell_exec|passthru|move_uploaded_file
```

### Step 7：性能与可靠性

对照 [performance-audit.md](performance-audit.md) + [architecture-patterns.md §4–5](architecture-patterns.md)：

- 读路径：N+1、无分页、Redis 缓存未鉴权命中
- 写路径：API 同步写重表、长事务内 HTTP、只改库不更缓存
- 异步：MQ confirm 前返回、双轨双消费、Poll 无限流、超时未补查就退款
- 缓存：穿透/击穿/雪崩；控制类 key TTL 与状态缓存混淆
- 前端：N+1 sign-url/manifest、in-flight 防抖 vs 永久禁生成

### Step 8：报告格式

使用 [report-template.md](report-template.md)。严重级别：

| 级别 | 含义 | 示例 |
|------|------|------|
| 🔴 Critical | 可直接被利用或确定资损 | SQL 注入、越权删数据、重复扣费 |
| 🟠 High | 高概率风险或合规缺失 | 无鉴权管理接口、密钥进仓库 |
| 🟡 Medium | 需条件触发或影响有限 | 缺限流、CSP 未配、日志含 PII |
| 🟢 Low | 加固项 | 依赖有小版本 CVE、注释含 TODO |

每条 finding 结构：

```markdown
### [级别] 标题
- **位置**: `path/to/file.py:123` 或 `ClassName.method`
- **问题**: 一句话描述
- **风险**: 攻击/资损场景
- **证据**: 代码片段或扫描输出摘要
- **修复**: 具体可执行建议（优先复用项目已有模式）
- **规范**: 对应 checklist 条目编号
```

## 专项场景（融合审查，不单列业务）

### 多租户 / 项目协同

→ [architecture-patterns §1、§3](architecture-patterns.md) + checklist-core §1.3

- membership 校验 + 子资源 `project_id` 二次绑定 + 非成员统一错误码
- billing_user ≠ actor；预扣锁按 billing 用户
- sign-url / OSS key 含 tenant 前缀且服务端校验归属

### 账本 / 算力 / 积分

→ [architecture-patterns §2–3](architecture-patterns.md)

- 三层防护 + 写顺序；reserve 成功后才返回提交成功
- quote 服务端权威；`commit_pending`/`release_pending` 可对账
- Redis 入口锁 fail-closed；禁止 localStorage 权威余额

### AI / 长时异步任务

→ [architecture-patterns §4、§9](architecture-patterns.md) + performance-audit §3

- 识别阶段：monolithic Worker **或** Submit/Poll+MQ（按已上线能力查）
- API 层固化 quote 快照；Submit 预扣后再 POST 上游
- Poll 全局限流；超时补查再 release；内部状态不泄露前端
- 双轨灰度：同 jobId 不双消费

### 独立部署 SaaS 存储

→ [architecture-patterns §5–7](architecture-patterns.md)

- MySQL 权威 + OSS 大对象 + Redis 非权威业务态
- HTTPS 签名 URL；生产禁 silent local fallback
- LLM/OSS 密钥集中加载，扫 `ai_read`、`*KEYS*.md` 明文

### 上线前快速验收

直接跑 [../code-security/15.上线Checklist.md](../code-security/15.上线Checklist.md)，在报告中标注 `[x]` / `[ ]` 及未通过项证据。

### 任意代码库快速体检

当项目不是典型 Web 应用时，仍按以下最小面审查：

- **输入边界**：命令行参数、文件上传/读取、环境变量、外部 URL、消息队列事件
- **执行边界**：shell、反序列化、模板渲染、插件加载、动态代码执行
- **数据边界**：密钥、PII、日志、缓存、临时文件、备份
- **发布边界**：CI、Docker、包管理、依赖锁、debug 配置
- **权限边界**：本地文件权限、云资源权限、服务账号、管理 API

## 审查原则

1. **先边界后漏洞**：无权威源/写顺序/clarity 不谈 OWASP 细节
2. **证据优先**：无代码/配置证据不写 finding
3. **后端为准**：UI 隐藏 ≠ 授权
4. **锁+幂等+顺序**：并发写查 L1 Redis → L2 行锁 → L3 UNIQUE + 写顺序表（architecture-patterns §2）
5. **Fail-closed 分路径**：资损路径 Redis down 必须 503；限流 down 常放行——标为缺口
6. **Redis 非权威**：加速/锁/验证码可以；扣费结果/任务终态不可以（DB+对账兜底）
7. **稳定错误码**：前端按 `code` 分支；禁止堆栈/SQL/内部状态枚举泄露
8. **修复对齐现有抽象**：`redis_mutex`、`credit_flow`、`fail(ErrorCode.*)` 等，不另起炉灶
9. **先报告风险再动修复**：除非用户明确要求修复，否则以审查 findings 为主；可给补丁建议但不静默改业务代码
10. **区分证据与推测**：没有直接证据但值得复核的内容放「待确认」，不要伪装成漏洞

## 附加资源

| 文档 | 用途 |
|------|------|
| [architecture-patterns.md](architecture-patterns.md) | **系统边界、并发、账本、异步、缓存（融合核心）** |
| [checklist-core.md](checklist-core.md) | 跨语言核心安全清单 |
| [stack-backend.md](stack-backend.md) | Python/Java/Go/Node 专项 |
| [stack-frontend.md](stack-frontend.md) | React/Vue/通用前端 |
| [performance-audit.md](performance-audit.md) | 性能与可靠性 |
| [checklist-infra.md](checklist-infra.md) | DB/Redis/部署/Nginx |
| [automation.md](automation.md) | Bandit/Semgrep/Trivy/CI |
| [report-template.md](report-template.md) | 完整报告模板 |
| [../code-security/](../code-security/) | 完整规范手册（17 篇） |
