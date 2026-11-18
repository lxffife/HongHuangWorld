<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, getToken, setToken } from './api'
import {
  DataAnalysis, User, Setting, Monitor, ChatDotRound, Warning, SwitchButton,
  Refresh, Plus, Key, Location
} from '@element-plus/icons-vue'

type AdminUser = {
  id: string
  username: string
  email?: string
  is_super_admin: boolean
  permissions?: string[] | null
}
type Permission = { key: string; name: string }
type AuthResult = { user: AdminUser; access_token: string; expires_at: string }

const token = ref(getToken())
const currentUser = ref<AdminUser | null>(null)
const activePage = ref('overview')
const loading = ref(false)
const users = ref<AdminUser[]>([])
const permissions = ref<Permission[]>([])
const loginForm = reactive({ username: '', password: '' })
const createVisible = ref(false)
const permissionVisible = ref(false)
const passwordVisible = ref(false)
const selectedUser = ref<AdminUser | null>(null)
const selectedPermissions = ref<string[]>([])
const createForm = reactive({ username: '', email: '', password: '' })
const passwordForm = reactive({ current_password: '', new_password: '' })

const isSuperAdmin = computed(() => !!currentUser.value?.is_super_admin)
const canReadUsers = computed(() => isSuperAdmin.value || !!currentUser.value?.permissions?.includes('admin_users.read'))
const canManageUsers = computed(() => isSuperAdmin.value || !!currentUser.value?.permissions?.includes('admin_users.manage'))
const menu = [
  { id: 'overview', label: '运营总览', icon: DataAnalysis },
  { id: 'users', label: '后台用户与权限', icon: User, permission: 'admin_users.read' },
  { id: 'players', label: '玩家管理', icon: User, soon: true },
  { id: 'worlds', label: '世界管理', icon: Location, soon: true },
  { id: 'servers', label: '服务器监控', icon: Monitor, soon: true },
  { id: 'monsters', label: '怪物管理', icon: Setting, soon: true },
  { id: 'chat', label: '聊天管理', icon: ChatDotRound, soon: true },
  { id: 'alerts', label: '告警与审计', icon: Warning, soon: true },
]
const visibleMenu = computed(() => menu.filter(item => !item.permission || canReadUsers.value))

async function login() {
  loading.value = true
  try {
    const result = await api<AuthResult>('/api/v1/admin/auth/login', {
      method: 'POST', body: JSON.stringify(loginForm),
    })
    setToken(result.access_token)
    token.value = result.access_token
    currentUser.value = result.user
    ElMessage.success('登录成功')
    await loadUsersIfAllowed()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '登录失败')
  } finally {
    loading.value = false
  }
}

async function restoreSession() {
  if (!token.value) return
  try {
    currentUser.value = await api<AdminUser>('/api/v1/admin/auth/me')
    await loadUsersIfAllowed()
  } catch {
    logout(false)
  }
}

function logout(showMessage = true) {
  setToken(null)
  token.value = ''
  currentUser.value = null
  users.value = []
  if (showMessage) ElMessage.success('已退出管理后台')
}

async function loadUsersIfAllowed() {
  if (!canReadUsers.value) return
  try {
    const result = await api<{ items: AdminUser[] }>('/api/v1/admin/users')
    users.value = result.items
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '读取后台用户失败')
  }
}

async function openCreateUser() {
  createForm.username = ''
  createForm.email = ''
  createForm.password = ''
  createVisible.value = true
}

async function createUser() {
  loading.value = true
  try {
    const created = await api<AdminUser>('/api/v1/admin/users', {
      method: 'POST', body: JSON.stringify(createForm),
    })
    ElMessage.success('后台用户已创建')
    createVisible.value = false
    await loadUsersIfAllowed()
    if (canManageUsers.value) await openPermissions(created)
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '创建用户失败')
  } finally {
    loading.value = false
  }
}

async function openPermissions(row: AdminUser) {
  if (row.is_super_admin) {
    ElMessage.warning('超级管理员权限不可通过普通用户授权界面修改')
    return
  }
  selectedUser.value = row
  selectedPermissions.value = [...(row.permissions ?? [])]
  try {
    const result = await api<{ items: Permission[] }>('/api/v1/admin/permissions')
    permissions.value = result.items
    permissionVisible.value = true
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '读取权限目录失败')
  }
}

async function savePermissions() {
  if (!selectedUser.value) return
  loading.value = true
  try {
    await api(`/api/v1/admin/users/${selectedUser.value.id}/permissions`, {
      method: 'PUT', body: JSON.stringify({ permissions: selectedPermissions.value }),
    })
    ElMessage.success('权限已更新')
    permissionVisible.value = false
    await loadUsersIfAllowed()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '权限更新失败')
  } finally {
    loading.value = false
  }
}

async function changePassword() {
  loading.value = true
  try {
    const result = await api<{ access_token: string }>('/api/v1/admin/auth/password', {
      method: 'POST', body: JSON.stringify(passwordForm),
    })
    setToken(result.access_token)
    token.value = result.access_token
    passwordVisible.value = false
    passwordForm.current_password = ''
    passwordForm.new_password = ''
    ElMessage.success('密码修改成功')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '密码修改失败')
  } finally {
    loading.value = false
  }
}

async function selectPage(id: string) {
  const item = menu.find(entry => entry.id === id)
  if (item?.soon) {
    ElMessage.info('该模块将在后续开发阶段接入')
    return
  }
  activePage.value = id
  if (id === 'users') await loadUsersIfAllowed()
}

onMounted(restoreSession)
</script>

<template>
  <div v-if="!currentUser" class="login-shell">
    <div class="login-glow"></div>
    <div class="login-card">
      <div class="brand-mark">洪</div>
      <div class="eyebrow">HONG HUANG WORLD · CONTROL CENTER</div>
      <h1>洪荒世界管理中枢</h1>
      <p class="login-subtitle">诸天运行 · 世界秩序 · 运营管理</p>
      <el-form label-position="top" @submit.prevent="login">
        <el-form-item label="后台用户名">
          <el-input v-model="loginForm.username" size="large" placeholder="输入管理员用户名" autocomplete="username" />
        </el-form-item>
        <el-form-item label="登录密码">
          <el-input v-model="loginForm.password" size="large" type="password" show-password placeholder="输入登录密码" autocomplete="current-password" @keyup.enter="login" />
        </el-form-item>
        <el-button class="login-button" type="primary" size="large" :loading="loading" @click="login">进入管理中枢</el-button>
      </el-form>
      <div class="login-foot">独立管理账号 · 安全会话认证</div>
    </div>
  </div>

  <el-container v-else class="admin-shell">
    <el-aside width="236px" class="sidebar">
      <div class="sidebar-brand">
        <div class="brand-mark small">洪</div>
        <div><strong>洪荒管理中枢</strong><small>ADMIN CONSOLE</small></div>
      </div>
      <div class="nav-caption">管理工作台</div>
      <el-menu :default-active="activePage" class="side-menu" @select="selectPage">
        <el-menu-item v-for="item in visibleMenu" :key="item.id" :index="item.id">
          <el-icon><component :is="item.icon" /></el-icon>
          <span>{{ item.label }}</span>
          <span v-if="item.soon" class="soon-tag">规划中</span>
        </el-menu-item>
      </el-menu>
      <div class="sidebar-bottom">
        <div class="connection-dot"></div>
        <span>管理 API 已连接</span>
        <span class="api-port">8790</span>
      </div>
    </el-aside>

    <el-container class="main-container">
      <el-header class="topbar">
        <div>
          <div class="breadcrumb">洪荒世界 <span>/</span> {{ menu.find(item => item.id === activePage)?.label }}</div>
          <div class="topbar-title">{{ menu.find(item => item.id === activePage)?.label }}</div>
        </div>
        <div class="top-actions">
          <el-tag effect="dark" type="success" round>{{ isSuperAdmin ? '超级管理员' : '运营用户' }}</el-tag>
          <el-dropdown>
            <div class="profile">
              <el-avatar :size="34">{{ currentUser.username.slice(0, 1).toUpperCase() }}</el-avatar>
              <div class="profile-name">{{ currentUser.username }}</div>
            </div>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item @click="passwordVisible = true"><el-icon><Key /></el-icon>修改密码</el-dropdown-item>
                <el-dropdown-item divided @click="logout()"><el-icon><SwitchButton /></el-icon>退出登录</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>

      <el-main class="content">
        <template v-if="activePage === 'overview'">
          <div class="welcome-row">
            <div><h2>欢迎回来，{{ currentUser.username }}</h2><p>掌握诸天世界运行状态，维护洪荒秩序。</p></div>
            <el-button :icon="Refresh" circle @click="restoreSession" />
          </div>
          <div class="metric-grid">
            <div class="metric-card"><div class="metric-label">当前在线玩家</div><div class="metric-value">--</div><div class="metric-note">实时统计接口 · P1 接入</div></div>
            <div class="metric-card"><div class="metric-label">运行中世界</div><div class="metric-value">--</div><div class="metric-note">世界实例监控 · P1 接入</div></div>
            <div class="metric-card"><div class="metric-label">WorldServer 节点</div><div class="metric-value">--</div><div class="metric-note">节点心跳监控 · P1 接入</div></div>
            <div class="metric-card"><div class="metric-label">待处理告警</div><div class="metric-value">--</div><div class="metric-note">告警中心 · 后续接入</div></div>
          </div>
          <div class="panel-grid">
            <section class="panel">
              <div class="panel-heading"><div><h3>世界运行状态</h3><p>全服世界和实例的在线情况</p></div><el-tag type="info">P1 接入</el-tag></div>
              <div class="empty-state"><div class="empty-orb">界</div><strong>世界监控数据尚未接入</strong><span>下一阶段将接入世界定义、实例心跳和在线玩家统计。</span></div>
            </section>
            <section class="panel">
              <div class="panel-heading"><div><h3>系统服务</h3><p>核心服务健康状态</p></div><el-tag type="info">P1 接入</el-tag></div>
              <div class="service-row"><span>Game API</span><el-tag type="success">当前管理 API 独立运行</el-tag></div>
              <div class="service-row"><span>ChatServer</span><el-tag type="info">监控待接入</el-tag></div>
              <div class="service-row"><span>WorldServer</span><el-tag type="info">监控待接入</el-tag></div>
            </section>
          </div>
          <section class="panel quick-panel">
            <div class="panel-heading"><div><h3>管理能力建设</h3><p>按阶段逐步开放真实数据和操作</p></div></div>
            <div class="phase-list"><span><i class="phase-done"></i>后台独立身份与权限</span><span><i class="phase-next"></i>玩家与世界实时监控</span><span><i></i>运维控制与游戏内容管理</span></div>
          </section>
        </template>

        <template v-else-if="activePage === 'users'">
          <div class="welcome-row">
            <div><h2>后台用户与权限</h2><p>由超级管理员创建后台用户，并为普通用户分配最小必要权限。</p></div>
            <el-button v-if="canManageUsers" type="primary" :icon="Plus" @click="openCreateUser">创建后台用户</el-button>
          </div>
          <section class="panel table-panel">
            <div class="panel-heading"><div><h3>后台账号</h3><p>后台账号与游戏玩家账号相互独立</p></div><el-button text :icon="Refresh" @click="loadUsersIfAllowed">刷新</el-button></div>
            <el-table :data="users" v-loading="loading" empty-text="暂无后台用户">
              <el-table-column prop="username" label="用户名" min-width="150" />
              <el-table-column prop="email" label="邮箱" min-width="190">
                <template #default="{ row }">{{ row.email || '—' }}</template>
              </el-table-column>
              <el-table-column label="账号类型" width="140">
                <template #default="{ row }"><el-tag :type="row.is_super_admin ? 'warning' : 'info'">{{ row.is_super_admin ? '超级管理员' : '普通用户' }}</el-tag></template>
              </el-table-column>
              <el-table-column label="已授予权限" min-width="260">
                <template #default="{ row }">
                  <span v-if="row.is_super_admin" class="muted">全部权限</span>
                  <div v-else class="permission-tags"><el-tag v-for="p in (row.permissions || []).slice(0, 3)" :key="p" size="small">{{ p }}</el-tag><span v-if="(row.permissions || []).length > 3" class="muted">+{{ (row.permissions || []).length - 3 }}</span><span v-if="!(row.permissions || []).length" class="muted">尚未授权</span></div>
                </template>
              </el-table-column>
              <el-table-column label="操作" width="130" fixed="right">
                <template #default="{ row }"><el-button v-if="canManageUsers && !row.is_super_admin" link type="primary" @click="openPermissions(row)">分配权限</el-button><span v-else class="muted">—</span></template>
              </el-table-column>
            </el-table>
          </section>
        </template>
      </el-main>
      <el-footer class="footer">HONG HUANG WORLD · ADMINISTRATION CONSOLE <span>独立管理服务 · 不参与游戏实时链路</span></el-footer>
    </el-container>
  </el-container>

  <el-dialog v-model="createVisible" title="创建后台用户" width="480px" append-to-body>
    <el-form label-position="top">
      <el-form-item label="用户名"><el-input v-model="createForm.username" maxlength="32" placeholder="3-32 位字母、数字或下划线" /></el-form-item>
      <el-form-item label="邮箱（可选）"><el-input v-model="createForm.email" placeholder="operator@example.com" /></el-form-item>
      <el-form-item label="初始密码"><el-input v-model="createForm.password" type="password" show-password placeholder="至少 12 位" /></el-form-item>
    </el-form>
    <template #footer><el-button @click="createVisible = false">取消</el-button><el-button type="primary" :loading="loading" @click="createUser">创建用户</el-button></template>
  </el-dialog>

  <el-dialog v-model="permissionVisible" :title="`分配权限 · ${selectedUser?.username || ''}`" width="620px" append-to-body>
    <p class="dialog-hint">未勾选的权限不会授予该用户。后台用户不能通过此页面给自己提权。</p>
    <el-checkbox-group v-model="selectedPermissions" class="permission-grid">
      <el-checkbox v-for="permission in permissions" :key="permission.key" :value="permission.key">
        <div class="permission-item"><strong>{{ permission.name }}</strong><small>{{ permission.key }}</small></div>
      </el-checkbox>
    </el-checkbox-group>
    <template #footer><el-button @click="permissionVisible = false">取消</el-button><el-button type="primary" :loading="loading" @click="savePermissions">保存权限</el-button></template>
  </el-dialog>

  <el-dialog v-model="passwordVisible" title="修改登录密码" width="440px" append-to-body>
    <el-form label-position="top">
      <el-form-item label="当前密码"><el-input v-model="passwordForm.current_password" type="password" show-password /></el-form-item>
      <el-form-item label="新密码"><el-input v-model="passwordForm.new_password" type="password" show-password placeholder="至少 12 位" /></el-form-item>
    </el-form>
    <template #footer><el-button @click="passwordVisible = false">取消</el-button><el-button type="primary" :loading="loading" @click="changePassword">修改密码</el-button></template>
  </el-dialog>
</template>
