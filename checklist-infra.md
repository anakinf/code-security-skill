# 基础设施与部署清单

**规范原文**: [../code-security/05.数据库安全.md](../code-security/05.数据库安全.md)、[06.Redis安全.md](../code-security/06.Redis安全.md)、[12.Docker部署.md](../code-security/12.Docker部署.md)、[13.Nginx配置.md](../code-security/13.Nginx配置.md)、[14.Linux安全.md](../code-security/14.Linux安全.md)

审查 `docker-compose*.yml`、`Dockerfile`、`nginx.conf`、`*.env.example`、部署脚本、systemd unit。

## 数据库

- [ ] 应用非 root；最小 GRANT
- [ ] 3306/5432 不对公网（安全组）
- [ ] SSL 连接（云 RDS 内网可据策略 N/A）
- [ ] 备份自动化 + 恢复演练记录
- [ ] `max_connections` 与连接池匹配

## Redis

- [ ] requirepass；bind 内网
- [ ] 危险命令 rename
- [ ] maxmemory + eviction policy
- [ ] 与 SMS/会话/业务 key 前缀隔离

## OSS / 对象存储

- [ ] Bucket 私有；ListObject 受限
- [ ] 应用 RAM 用户最小权限
- [ ] 内网 endpoint 用于服务端；HTTPS 签名给浏览器

## Docker

- [ ] 非 root USER
- [ ] 只读根文件系统（若可行）
- [ ] cap-drop；资源 limit
- [ ] 镜像扫描（Trivy）；无 latest 漂移
- [ ] 密钥经 env/secret 注入，不进镜像层

## Nginx / 网关

- [ ] TLS 1.2+；HSTS
- [ ] `client_max_body_size` 与业务一致
- [ ] 安全头：X-Frame-Options, X-Content-Type-Options, CSP, Referrer-Policy
- [ ] 限流 `limit_req`（至少登录/SMS）
- [ ] 禁止 `.git`、`.env` 直出

## Linux / 网络

- [ ] SSH 仅运维 IP（据项目基线）
- [ ] 安全组最小端口（80/443；DB/Redis/MQ 仅 VPC）
- [ ] MQ 管理口不对公网
- [ ] 时区与日志一致（业务时区统一）

## HTTPS

- [ ] 证书有效 + 自动续期
- [ ] HTTP → HTTPS 跳转

## 环境变量审计

搜索代码库：

```
grep -riE 'password|secret|api_key|private_key' --include='*.env*' --include='*.yml'
```

- [ ] `.env` 在 `.gitignore`
- [ ] example 文件无真实凭证
- [ ] 生产 `DEBUG=false`、mock 认证关闭
