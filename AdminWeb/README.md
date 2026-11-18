# 洪荒世界管理后台前端

技术栈：Vue 3、TypeScript、Vite、Element Plus。

## 本地开发

1. 确保 PostgreSQL 已启动并执行数据库迁移 000041。
2. 配置 Deployment/.env 中的后台超级管理员初始化信息。
3. 启动 Admin API：Windows 执行 Deployment/start-admin-server.ps1；Linux 执行 bash Deployment/start-admin-server.sh。
4. 在本目录执行 npm install。
5. 执行 npm run dev，使用浏览器打开 Vite 输出的本机地址。

Vite 开发服务器将 /api、/health、/ready 代理到本机 127.0.0.1:8790。

## 当前范围

当前界面提供后台登录、会话恢复、运营总览占位、后台用户创建、直接权限分配和修改本人密码。玩家、世界、怪物、服务控制和聊天管理页面会在对应后端阶段完成后逐步接入。

生产部署应使用 HTTPS 反向代理，并确保管理 API 不直接暴露公网。
