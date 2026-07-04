# 自动化扫描

**规范原文**: [../code-security/16.自动化扫描.md](../code-security/16.自动化扫描.md)

## 快速脚本

```bash
bash scripts/scan.sh /path/to/project
```

脚本会检测栈并运行可用工具；缺失工具时跳过并提示安装。扫描仅作为证据入口，不能代替权限、业务幂等、缓存一致性和架构边界人工审查。

## 按语言

### Python

```bash
pip install bandit pip-audit semgrep 2>/dev/null
bandit -r . -ll -x ./venv,./node_modules,./.git 2>/dev/null || true
pip-audit -r requirements.txt 2>/dev/null || pip-audit 2>/dev/null || true
semgrep --config=registry/owasp-top-ten --error --quiet . 2>/dev/null || true
```

关注 Bandit 规则：B102 exec, B201 eval, B301 pickle, B506 yaml.load, B608 SQL, B602 subprocess。

### Node.js

```bash
npm audit --audit-level=high 2>/dev/null || pnpm audit --audit-level high 2>/dev/null || true
npx --yes depcheck 2>/dev/null || true   # 未使用依赖（可选）
```

### Java

```bash
# 需项目已配置 OWASP dependency-check 插件
mvn -q org.owasp:dependency-check-maven:check 2>/dev/null || true
```

### .NET

```bash
dotnet list package --vulnerable --include-transitive 2>/dev/null || true
dotnet list package --deprecated 2>/dev/null || true
```

关注：`Microsoft.AspNetCore.*` 过旧、JSON 反序列化、Swagger/Debug 生产暴露、连接串明文。

### PHP

```bash
composer audit 2>/dev/null || true
composer validate --no-check-publish 2>/dev/null || true
```

关注：Laravel/Symfony 版本、debug、`.env` 泄露、上传目录执行权限。

### Go

```bash
go install golang.org/x/vuln/cmd/govulncheck@latest 2>/dev/null
govulncheck ./... 2>/dev/null || true
```

### 容器 / 文件系统

```bash
trivy fs --severity HIGH,CRITICAL --exit-code 0 .
```

## Semgrep 自定义（可选）

项目根 `.semgrep/` 可放团队规则，例如：

```yaml
rules:
  - id: missing-auth-decorator
    pattern-either:
      - pattern: |
          @$METHOD($PATH)
          def $FUNC(...):
              ...
    metavariable-regex:
      METHOD: (get|post|put|delete|patch)
    message: "路由可能缺少认证依赖"
    languages: [python]
    severity: WARNING
```

## CI 门禁建议

| 阶段 | 工具 | 失败条件 |
|------|------|----------|
| pre-commit | bandit / eslint security | HIGH |
| PR | semgrep owasp-top-ten | ERROR 规则 |
| merge | trivy, pip-audit, npm audit | CRITICAL |
| 每周 | 全量 + Dependabot | 人工 triage |

## 通用 grep 快速包

自动化工具不可用时，至少跑：

```bash
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'eval\(|exec\(|shell=True|ProcessBuilder|exec.Command|shell_exec|passthru|unserialize\(|BinaryFormatter|dangerouslySetInnerHTML|v-html|innerHTML|AKIA[0-9A-Z]{16}|BEGIN .*PRIVATE KEY|password\s*=|api[_-]?key\s*=' .
```

命中结果必须人工确认上下文；测试样例、假密钥、文档说明不直接作为漏洞。

## 扫描结果写入报告

自动化输出摘要表：

| 工具 | 状态 | HIGH+ 数量 | 备注 |
|------|------|------------|------|
| bandit | pass/fail/skip | N | |
| npm audit | | | |

**人工必跟进的 gap**（工具扫不出）：

- 越权与 IDOR
- 业务幂等与资损
- 架构双消费/缓存一致性
- 权限模型完整性
