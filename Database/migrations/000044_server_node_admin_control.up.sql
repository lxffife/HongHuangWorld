BEGIN;
ALTER TABLE server_registry
    ADD COLUMN admin_state VARCHAR(16) NOT NULL DEFAULT 'normal'
    CHECK (admin_state IN ('normal', 'draining', 'disabled'));

INSERT INTO admin_permissions(permission_key, name, description)
VALUES ('servers.manage', '管理世界服务器节点', '查看节点、设置维护排水和禁用节点')
ON CONFLICT (permission_key) DO NOTHING;

INSERT INTO admin_role_permissions(role_id, permission_key)
SELECT id, 'servers.manage' FROM admin_roles WHERE role_key = 'super_admin'
ON CONFLICT DO NOTHING;
COMMIT;
