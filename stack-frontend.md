# 前端栈专项审查

**规范原文**: [../code-security/07.React安全.md](../code-security/07.React安全.md)

适用 React、Vue、Angular、Svelte 等；条目按框架映射。

## 构建与发布

- [ ] 生产无 source map（或仅内网）
- [ ] 移除 console/debugger（或 build 插件剥离）
- [ ] 环境变量：仅 `VITE_*`/`NEXT_PUBLIC_*` 进客户端；密钥不进 bundle
- [ ] 依赖 lockfile；`npm audit` / `pnpm audit`
- [ ] CSP、HSTS 由 Nginx 或 meta（见 infra 清单）

## XSS

| 框架 | 危险 API | 缓解 |
|------|----------|------|
| React | `dangerouslySetInnerHTML` | DOMPurify |
| Vue | `v-html` | DOMPurify / 禁止不可信 HTML |
| Angular | `[innerHTML]` binding | DomSanitizer |
| 通用 | `document.write`, `eval`, `new Function` | 禁止 |

- [ ] URL 参数进 DOM 前 encode
- [ ] `javascript:` 协议链接过滤
- [ ] Markdown 渲染器配置 sanitize

## CSRF / 会话

- [ ] Token 优先 HttpOnly Cookie 或内存；localStorage 存 JWT 为已知风险
- [ ] SameSite Cookie；跨站关键操作用 CSRF token
- [ ] 退出清除客户端状态 + 调服务端 logout

## 授权与 UX

- [ ] **UI 隐藏 ≠ 安全**；须注明「后端已校验」或标为 UX-only
- [ ] 路由 guard 与 API 401 处理一致
- [ ] 多租户：URL 中 projectId 变更时清缓存、重鉴权

## 敏感数据

- [ ] 不在前端维护权威余额（展示可缓存，提交前拉最新）
- [ ] 不在代码硬编码 API Key
- [ ] 错误提示不展示原始 stack（仅 dev overlay）

## 请求层

- [ ] 统一 API client：401 跳登录、429 提示、402 引导充值
- [ ] 按 `err.code` 分支，非 `message.includes(...)`
- [ ] 生成/支付提交带幂等键或 quoteToken
- [ ] 防重复提交：in-flight 禁用按钮（**不能替代**后端幂等）

## 性能相关安全边界

- [ ] 大列表虚拟滚动；避免一次渲染万级 DOM（DoS 自身）
- [ ] 上传前端校验类型/大小（**后端仍须校验**）
- [ ] 轮询间隔合理；WebSocket 断线不重连风暴
- [ ] React Query/SWR：`staleTime` 避免 N+1 重复拉 manifest

## Vue 补充

- [ ] 生产关闭 Vue DevTools 暴露（若可配置）
- [ ] `server.middleware` SSR 时校验 cookie 与 CSRF

## Angular 补充

- [ ] `bypassSecurityTrust*` 使用审计
- [ ] HttpInterceptor 统一附 token、处理 401
