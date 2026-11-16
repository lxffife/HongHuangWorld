# 树莓派部署说明（HongHuangWorld P0）

本文对应 feature/p0-foundation 分支。目标环境为 Raspberry Pi 4B/5、8GB 内存、64 位 Raspberry Pi OS / Debian（aarch64）。Go API、PostgreSQL、Redis、NATS 和 C++ ENet WorldServer 运行在树莓派；Godot 客户端仍在 Windows PC 上运行。

> 当前是 P0 联网垂直切片测试环境，不是公网生产部署方案。建议先在家庭/实验室局域网验证。

## 1. 部署拓扑

| 组件 | 运行方式 | 端口 | 用途 |
|---|---|---:|---|
| Go API | systemd | TCP 8787 | 注册、登录、灵魂、角色、世界入口 |
| C++ WorldServer | systemd | UDP 7777 | ENet 实时游戏连接 |
| PostgreSQL 17 | Docker Compose | TCP 5432 | 游戏业务数据 |
| Redis 7 | Docker Compose | TCP 6379 | 后续缓存预留 |
| NATS 2 | Docker Compose | TCP 4222 | 后续消息通信预留 |
| NATS monitor | Docker Compose | TCP 8222 | 运维检查 |

当前 Go API 直接使用 PostgreSQL。Redis 和 NATS 会随部署启动，但当前并非所有业务流程都已接入它们。

客户端通过 HTTP 8787 访问树莓派，再使用 API 返回的游戏服地址和 UDP 7777 连接 WorldServer。WORLD_SERVER_BIND 是服务器监听地址，WORLD_SERVER_ADVERTISE_HOST 则必须填写 Windows 客户端能够访问的树莓派局域网 IP。

## 2. 树莓派系统准备

建议使用 Raspberry Pi OS Lite 64-bit（Bookworm 或更新版本）或 Debian 12+ ARM64。建议有线网络、稳定供电和散热，最好使用 SSD；建议至少预留 16GB 空间。

确认架构：

    uname -m
    getconf LONG_BIT

应分别输出 aarch64 和 64。当前脚本不支持 32 位 ARM（例如 armv7l）。

更新系统：

    sudo apt update
    sudo apt full-upgrade -y
    sudo reboot

查看树莓派 IP：

    hostname -I

建议在路由器中为树莓派设置 DHCP 地址保留，避免重启后 IP 改变。

## 3. GitHub Token 权限

仓库为私有仓库时，建议创建 Fine-grained Personal Access Token：
- Repository access：只选择 liflife/HongHuangWorld。
- Repository permissions：Contents: Read-only。
- 不需要 Actions、Administration、Issues 等权限。
- 不要把 Token 提交到仓库、写进 URL 或发到聊天中。

部署脚本运行时会静默提示输入 Token，并通过临时 Git askpass 文件执行 clone/fetch。Token 不会写入 Git remote URL 或项目文件；临时认证文件在脚本退出时清理。

## 4. 网络代理配置

部署脚本默认使用你提供的局域网 HTTP 代理：

    http://192.168.124.16:17891

脚本会在安装依赖前完成以下配置：
- 当前部署进程的 HTTP_PROXY / HTTPS_PROXY / ALL_PROXY，供 Git、curl 和 Go 下载使用。
- APT 持久配置 `/etc/apt/apt.conf.d/99honghuang-proxy`，确保 `sudo apt-get update/install` 走代理。
- Docker systemd drop-in：`/etc/systemd/system/docker.service.d/http-proxy.conf`，使 Docker 守护进程拉取镜像时也使用代理。

代理配置会保留在树莓派上，后续 APT 和 Docker 操作也会继续使用。树莓派必须能够访问代理主机的 IP 和端口；可先测试：

    curl -I -x http://192.168.124.16:17891 https://github.com

如需临时改用其他代理：

    HH_PROXY_URL=http://代理IP:端口 ~/deploy-raspberry-pi.sh

如不使用代理：

    HH_PROXY_URL= ~/deploy-raspberry-pi.sh

脚本默认只有在 APT 软件包索引不存在或超过 6 小时时才执行 `apt-get update`，避免每次部署重复下载索引。需要强制刷新时：

    HH_FORCE_APT_UPDATE=1 ~/deploy-raspberry-pi.sh

如果以后要移除持久代理配置：

    sudo rm -f /etc/apt/apt.conf.d/99honghuang-proxy
    sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
    sudo systemctl daemon-reload
    sudo systemctl restart docker

注意：Docker 镜像拉取由 Docker daemon 执行，因此仅设置当前终端的代理变量不足以保证 Docker 拉取镜像走代理；脚本已单独配置 daemon。

## 5. 获取并运行脚本

脚本已放入仓库：
- Deployment/deploy-raspberry-pi.sh

首次部署时仓库还没有克隆，因此先在有仓库访问权限的电脑上打开 GitHub 的 feature/p0-foundation 分支，下载该脚本，再通过 SCP、U 盘或 SSH 编辑器复制到树莓派用户家目录。

在树莓派执行：

    chmod +x ~/deploy-raspberry-pi.sh
    ~/deploy-raspberry-pi.sh

不要用 sudo 运行整个脚本。脚本会在需要时调用 sudo。运行时按提示输入 GitHub Token，输入过程不会回显。

脚本自动完成：
1. 检查 ARM64 架构。
2. 安装编译依赖、Docker Engine、Compose。
3. 安装固定版本 Go 1.24.0（ARM64）。
4. 拉取 feature/p0-foundation 分支，或询问是否更新已有工作区。
5. 首次生成数据库密码、Redis 密码和 WorldServer API key。
6. 启动 PostgreSQL、Redis、NATS 并等待数据库就绪。
7. 创建迁移账本并按顺序执行尚未应用的 SQL migration。
8. 编译 Go API 和 C++ WorldServer。
9. 执行 C++ 协议与移动测试。
10. 安装并启动 systemd 服务。

默认仓库目录是 ~/HongHuangWorld。需要改目录时：

    HH_INSTALL_DIR="$HOME/apps/HongHuangWorld" ~/deploy-raspberry-pi.sh

如果自动识别的局域网 IP 不正确，可指定：

    HH_ADVERTISE_HOST=192.168.1.50 ~/deploy-raspberry-pi.sh

请将示例地址替换成树莓派实际 IP。

## 6. 环境配置

密钥和运行配置保存在：

    /etc/honghuang-world.env

文件由运行部署脚本的 Linux 用户持有，权限为 600（仅该用户可读写）；systemd 由系统管理器读取。查看：

    sudo less /etc/honghuang-world.env

如果树莓派 IP 变化，编辑 WORLD_SERVER_ADVERTISE_HOST：

    sudo nano /etc/honghuang-world.env
    sudo systemctl restart honghuang-world-server

修改 WORLD_SERVER_API_KEY 时，Go API 和 WorldServer 共用同一个环境文件，需重启两个服务：

    sudo systemctl restart honghuang-api honghuang-world-server

修改世界 ID、节点标识或端口后，也应重启相应服务。默认 WORLD_ID 为 qingyun_human。

## 7. 网络与 Windows 客户端

局域网客户端至少需要访问：
- TCP 8787：HTTP API。
- UDP 7777：ENet 游戏连接。

如果树莓派启用了 UFW：

    sudo ufw allow 8787/tcp
    sudo ufw allow 7777/udp
    sudo ufw status

Windows Godot 客户端 API Base URL 填写：

    http://树莓派局域网IP:8787

例如：

    http://192.168.1.50:8787

不要填写 127.0.0.1（它指向 Windows 自己），也不要填写 0.0.0.0。WorldServer 返回给客户端的地址同样由 WORLD_SERVER_ADVERTISE_HOST 决定。

PostgreSQL 5432、Redis 6379、NATS 4222/8222 在 Compose 中绑定到 127.0.0.1，不接受局域网远程连接。不要配置路由器公网端口转发。当前方案没有配置 TLS、反向代理和生产级密钥管理。

## 8. 部署检查

查看服务：

    sudo systemctl status honghuang-api
    sudo systemctl status honghuang-world-server

查看容器：

    docker compose --env-file /etc/honghuang-world.env \
      -f ~/HongHuangWorld/Deployment/docker-compose.yml ps

如果仓库安装在其他目录，请替换上面的路径。

检查 API：

    curl -i http://127.0.0.1:8787/health
    curl -i http://127.0.0.1:8787/ready

预期 HTTP 200，JSON 状态分别为 ok 和 ready。从 Windows 浏览器也应能打开：

    http://树莓派IP:8787/ready

查看 WorldServer 日志，确认节点启动并成功向中心服发送 heartbeat：

    sudo journalctl -u honghuang-world-server -n 100 --no-pager

查看迁移记录：

    docker compose --env-file /etc/honghuang-world.env \
      -f ~/HongHuangWorld/Deployment/docker-compose.yml \
      exec -T postgres psql -U honghuang -d honghuang \
      -c "SELECT version, applied_at FROM schema_migrations ORDER BY version;"

应能看到所有已应用的迁移版本。

## 9. 日志、启停与更新

实时查看 API：

    sudo journalctl -u honghuang-api -f

实时查看 WorldServer：

    sudo journalctl -u honghuang-world-server -f

重启：

    sudo systemctl restart honghuang-api
    sudo systemctl restart honghuang-world-server

停止游戏服务：

    sudo systemctl stop honghuang-world-server honghuang-api

启动：

    sudo systemctl start honghuang-api
    sudo systemctl start honghuang-world-server

再次运行部署脚本会询问是否拉取 feature/p0-foundation 最新代码，随后重新编译并重启服务。迁移账本会跳过已经成功执行的版本。更新前仍建议先备份数据库。

## 10. 数据备份与恢复

备份：

    mkdir -p ~/honghuang-backups
    docker compose --env-file /etc/honghuang-world.env \
      -f ~/HongHuangWorld/Deployment/docker-compose.yml \
      exec -T postgres pg_dump -U honghuang -d honghuang \
      > ~/honghuang-backups/honghuang-$(date +%F-%H%M).sql

恢复前停止 API 和 WorldServer，并确认目标数据库：

    sudo systemctl stop honghuang-world-server honghuang-api
    cat ~/honghuang-backups/备份文件.sql | docker compose \
      --env-file /etc/honghuang-world.env \
      -f ~/HongHuangWorld/Deployment/docker-compose.yml \
      exec -T postgres psql -U honghuang -d honghuang
    sudo systemctl start honghuang-api honghuang-world-server

不要使用 docker compose down -v 清理重装，否则会删除数据库持久化卷。部署脚本不会执行该命令。

## 11. 常见问题

### Token 无法拉取仓库
确认 Token 未过期、仓库范围选择正确、Contents: Read-only 权限已授予，并确认组织策略允许该 Token。

### 架构不是 aarch64
安装 64 位 Raspberry Pi OS。当前脚本不支持 32 位系统。

### Go 下载或编译失败
脚本固定下载 Go 1.24.0 ARM64。确认树莓派可以访问 go.dev，并有足够磁盘空间。

### CMake 找不到依赖

    sudo apt update
    sudo apt install -y libenet-dev libcurl4-openssl-dev nlohmann-json3-dev pkg-config cmake

然后重新运行部署脚本。

### API 启动失败

    sudo journalctl -u honghuang-api -n 200 --no-pager

检查 DATABASE_URL 密码是否与 POSTGRES_PASSWORD 一致、PostgreSQL 是否健康、迁移是否完成。

### 客户端提示没有可用世界服务器

    sudo journalctl -u honghuang-world-server -n 200 --no-pager
    sudo journalctl -u honghuang-api -n 200 --no-pager

检查 WORLD_SERVER_API_KEY 是否正确、WORLD_ID 是否为 qingyun_human、WORLD_SERVER_ADVERTISE_HOST 是否为客户端可访问 IP、UDP 7777 是否放行，以及 WorldServer heartbeat 是否成功。

### 8787 可访问但游戏 UDP 连接失败
HTTP 和 ENet 使用不同协议。确认防火墙放行 UDP 7777，而不只是 TCP 8787。

## 12. 当前部署边界

- 这是单树莓派部署：中心 API、数据库和一个青云人界 WorldServer。
- Pi 4B 8GB 适合基础联网闭环测试，不代表能够承载高并发或最终高品质 3D 场景。
- Godot 客户端在 Windows PC 运行，树莓派不运行 Godot 编辑器。
- Redis、NATS 已启动，但当前并非所有业务逻辑都使用它们。
- 尚未配置公网 TLS、反向代理、自动证书、异地备份、监控告警和生产级密钥轮换。不要直接暴露到公网。
- 首轮测试建议依次验证注册、登录、创建灵魂、创建角色、进入青云人界，再使用第二台客户端测试多人可见和移动同步。
