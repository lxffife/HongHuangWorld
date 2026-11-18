BEGIN;
CREATE TABLE admin_users (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 username VARCHAR(32) NOT NULL,
 email VARCHAR(254),
 password_hash TEXT NOT NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
 is_super_admin BOOLEAN NOT NULL DEFAULT FALSE,
 created_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
 last_login_at TIMESTAMPTZ,
 password_changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (length(username) BETWEEN 3 AND 32)
);
CREATE UNIQUE INDEX uq_admin_users_username_ci ON admin_users(lower(username));
CREATE UNIQUE INDEX uq_admin_users_email_ci ON admin_users(lower(email)) WHERE email IS NOT NULL;
CREATE TABLE admin_roles (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 role_key VARCHAR(48) NOT NULL UNIQUE,
 name VARCHAR(96) NOT NULL,
 description TEXT NOT NULL DEFAULT '',
 is_system BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE admin_permissions (
 permission_key VARCHAR(96) PRIMARY KEY,
 name VARCHAR(96) NOT NULL,
 description TEXT NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE admin_user_roles (
 user_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
 role_id UUID NOT NULL REFERENCES admin_roles(id) ON DELETE CASCADE,
 granted_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (user_id, role_id)
);
CREATE TABLE admin_role_permissions (
 role_id UUID NOT NULL REFERENCES admin_roles(id) ON DELETE CASCADE,
 permission_key VARCHAR(96) NOT NULL REFERENCES admin_permissions(permission_key) ON DELETE CASCADE,
 PRIMARY KEY (role_id, permission_key)
);
CREATE TABLE admin_user_permissions (
 user_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
 permission_key VARCHAR(96) NOT NULL REFERENCES admin_permissions(permission_key) ON DELETE CASCADE,
 granted_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (user_id, permission_key)
);
CREATE TABLE admin_sessions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
 token_hash BYTEA NOT NULL UNIQUE,
 expires_at TIMESTAMPTZ NOT NULL,
 revoked_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admin_sessions_user ON admin_sessions(user_id);
CREATE INDEX idx_admin_sessions_expiry ON admin_sessions(expires_at);
CREATE TABLE admin_audit_logs (
 id BIGSERIAL PRIMARY KEY,
 actor_user_id UUID REFERENCES admin_users(id) ON DELETE SET NULL,
 action VARCHAR(96) NOT NULL,
 resource_type VARCHAR(64) NOT NULL,
 resource_id VARCHAR(128) NOT NULL DEFAULT '',
 result VARCHAR(16) NOT NULL CHECK (result IN ('success','failure','denied')),
 details JSONB NOT NULL DEFAULT '{}'::jsonb,
 remote_addr INET,
 user_agent VARCHAR(512) NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admin_audit_logs_created ON admin_audit_logs(created_at DESC);
CREATE INDEX idx_admin_audit_logs_actor ON admin_audit_logs(actor_user_id, created_at DESC);
CREATE INDEX idx_admin_audit_logs_resource ON admin_audit_logs(resource_type, resource_id, created_at DESC);
INSERT INTO admin_permissions(permission_key, name, description) VALUES
('dashboard.read','查看运营总览','查看在线人数、世界和服务概况'),
('players.read','查看玩家','搜索和查看玩家资料'),
('players.manage','管理玩家','修改允许管理的玩家资料'),
('players.ban','封禁玩家','封禁和解封玩家账号'),
('players.kick','强制下线','终止玩家当前活动会话'),
('worlds.read','查看世界','查看世界、实例和在线状态'),
('worlds.manage','管理世界','修改世界运营状态和配置'),
('servers.read','查看服务器','查看节点、心跳和服务指标'),
('servers.control','控制服务器','启动、停止和重启受管服务'),
('monsters.read','查看怪物','查看怪物模板和刷新配置'),
('monsters.manage','管理怪物','新增、编辑、启用和禁用怪物'),
('game_config.read','查看游戏配置','查看游戏运营配置'),
('game_config.manage','管理游戏配置','修改、发布和回滚配置版本'),
('chat.read','查看聊天','查询聊天消息和聊天状态'),
('chat.manage','管理聊天','执行授权的聊天管理操作'),
('alerts.read','查看告警','查看服务异常和告警记录'),
('alerts.manage','管理告警','确认和处理告警'),
('audit.read','查看审计','查看后台操作审计记录'),
('admin_users.read','查看后台用户','查看后台用户及权限'),
('admin_users.manage','管理后台用户','创建后台用户、分配角色和权限、禁用用户')
ON CONFLICT (permission_key) DO NOTHING;
INSERT INTO admin_roles(role_key, name, description, is_system) VALUES
('super_admin','超级管理员','拥有全部后台管理权限',TRUE),
('operator','运营人员','由超级管理员分配具体运营权限',TRUE)
ON CONFLICT (role_key) DO NOTHING;
INSERT INTO admin_role_permissions(role_id, permission_key)
SELECT r.id, p.permission_key FROM admin_roles r CROSS JOIN admin_permissions p
WHERE r.role_key='super_admin' ON CONFLICT DO NOTHING;
COMMIT;
