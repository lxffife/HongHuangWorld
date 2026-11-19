BEGIN;
DELETE FROM admin_role_permissions WHERE permission_key = 'servers.manage';
DELETE FROM admin_user_permissions WHERE permission_key = 'servers.manage';
DELETE FROM admin_permissions WHERE permission_key = 'servers.manage';
ALTER TABLE server_registry DROP COLUMN admin_state;
COMMIT;
