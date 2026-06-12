// ===== API 설정 =====
const API_BASE = "https://insight-now-app.onrender.com";
let currentToken = null;
let keywords = [];

// ===== 로그인 =====
async function login() {
    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;

    if (!email || !password) {
        showAlert('이메일과 비밀번호를 입력해주세요', 'error', 'login-alert');
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password })
        });

        const data = await res.json();

        if (!res.ok) {
            showAlert('로그인 실패: ' + data.detail, 'error', 'login-alert');
            return;
        }

        currentToken = data.access_token;
        localStorage.setItem('admin-token', currentToken);
        localStorage.setItem('admin-email', email);

        document.getElementById('login-section').style.display = 'none';
        document.getElementById('dashboard-section').style.display = 'block';

        loadDashboard();
        showAlert('로그인 성공!', 'success', 'alert');

    } catch (error) {
        showAlert('서버 연결 실패', 'error', 'login-alert');
    }
}

function logout() {
    localStorage.removeItem('admin-token');
    localStorage.removeItem('admin-email');
    location.reload();
}

// ===== 알림 =====
function showAlert(message, type, elementId = 'alert') {
    const alert = document.getElementById(elementId);
    alert.textContent = message;
    alert.className = `alert ${type}`;
    alert.style.display = 'block';
    setTimeout(() => alert.style.display = 'none', 3000);
}

// ===== 탭 전환 =====
function switchTab(tabId) {
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    document.querySelectorAll('.nav-tabs button').forEach(b => b.classList.remove('active'));
    
    document.getElementById(tabId).classList.add('active');
    event.target.classList.add('active');
}

// ===== 글 관리 =====
function togglePriceInput() {
    const accessType = document.getElementById('post-access').value;
    document.getElementById('price-group').style.display = 
        accessType === 'paid_single' ? 'block' : 'none';
}

async function createPost() {
    const title = document.getElementById('post-title').value;
    const content = document.getElementById('post-content').value;
    const category = document.getElementById('post-category').value;

    if (!title || !content) {
        showAlert('제목과 본문을 입력해주세요', 'error');
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/posts/admin/create`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'authorization': `Bearer ${currentToken}`
            },
            body: JSON.stringify({
                title,
                preview: document.getElementById('post-preview').value,
                content,
                category: category,
                access_type: document.getElementById('post-access').value,
                single_price: document.getElementById('post-access').value === 'paid_single' 
                    ? parseInt(document.getElementById('post-price').value) 
                    : null
            })
        });

        if (res.ok) {
            showAlert('✅ 글이 발행되었습니다!', 'success');
            // 입력 초기화
            document.getElementById('post-title').value = '';
            document.getElementById('post-preview').value = '';
            document.getElementById('post-content').value = '';
            loadPosts();
        } else {
            const err = await res.json();
            showAlert('발행 실패: ' + err.detail, 'error');
        }
    } catch (error) {
        showAlert('오류 발생', 'error');
    }
}

async function loadPosts() {
    try {
        const res = await fetch(`${API_BASE}/posts/`);
        const data = await res.json();
        const tbody = document.getElementById('posts-list');
        
        if (!data.posts || data.posts.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#aaa;">발행된 글이 없습니다</td></tr>';
            return;
        }

        tbody.innerHTML = data.posts.map(post => `
            <tr>
                <td>${post.title || '-'}</td>
                <td>${post.view_count || 0}</td>
                <td>${post.purchase_count || 0}</td>
                <td>₩${(post.revenue || 0).toLocaleString('ko-KR')}</td>
                <td>${post.access_type || '-'}</td>
                <td>${new Date(post.published_at).toLocaleDateString('ko-KR')}</td>
                <td>
                    <button class="danger" onclick="deletePost('${post.id}')" style="padding:5px 10px;font-size:12px;">삭제</button>
                </td>
            </tr>
        `).join('');
    } catch (error) {
        console.error('글 로드 실패', error);
    }
}

async function deletePost(postId) {
    if (!confirm('정말 삭제하시겠습니까?')) return;

    try {
        const res = await fetch(`${API_BASE}/posts/${postId}`, {
            method: 'DELETE',
            headers: { 'authorization': `Bearer ${currentToken}` }
        });

        if (res.ok) {
            showAlert('글이 삭제되었습니다', 'success');
            loadPosts();
        }
    } catch (error) {
        showAlert('삭제 실패', 'error');
    }
}

// ===== 키워드 관리 =====
function addKeyword() {
    const input = document.getElementById('new-keyword');
    const keyword = input.value.trim();

    if (!keyword) {
        showAlert('키워드를 입력해주세요', 'error');
        return;
    }

    if (!keywords.includes(keyword)) {
        keywords.push(keyword);
        input.value = '';
        renderKeywords();
        showAlert('✅ 키워드가 추가되었습니다', 'success');
        saveKeywords();
    }
}

function removeKeyword(keyword) {
    keywords = keywords.filter(k => k !== keyword);
    renderKeywords();
    saveKeywords();
}

function renderKeywords() {
    const list = document.getElementById('keyword-list');
    if (keywords.length === 0) {
        list.innerHTML = '<p style="color:#aaa;">키워드를 추가해주세요</p>';
        return;
    }

    list.innerHTML = keywords.map(kw => `
        <div class="keyword-tag">
            ${kw}
            <button onclick="removeKeyword('${kw}')" title="제거">✕</button>
        </div>
    `).join('');
}

function saveKeywords() {
    localStorage.setItem('admin-keywords', JSON.stringify(keywords));
}

function loadKeywords() {
    const saved = localStorage.getItem('admin-keywords');
    keywords = saved ? JSON.parse(saved) : [];
    renderKeywords();
}

async function saveNewsSettings() {
    showAlert('설정이 저장되었습니다', 'success');
}

// ===== 고객 관리 =====
async function loadCustomers() {
    try {
        const res = await fetch(`${API_BASE}/admin/users`, {
            headers: { 'authorization': `Bearer ${currentToken}` }
        });

        const data = await res.json();
        const tbody = document.getElementById('customers-list');

        if (!data.users || data.users.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#aaa;">고객이 없습니다</td></tr>';
            return;
        }

        tbody.innerHTML = data.users.map(user => `
            <tr>
                <td>${user.email}</td>
                <td>
                    <select onchange="updateUserRole('${user.id}', this.value)">
                        <option value="user" ${user.role === 'user' ? 'selected' : ''}>일반</option>
                        <option value="premium" ${user.role === 'premium' ? 'selected' : ''}>프리미엄</option>
                        <option value="admin" ${user.role === 'admin' ? 'selected' : ''}>관리자</option>
                    </select>
                </td>
                <td>${user.role === 'premium' ? '✅ 구독중' : '❌ 미구독'}</td>
                <td>${new Date(user.created_at).toLocaleDateString('ko-KR')}</td>
                <td>
                    <button class="danger" onclick="deleteCustomer('${user.id}')" style="padding:5px 10px;font-size:12px;">삭제</button>
                </td>
            </tr>
        `).join('');
    } catch (error) {
        console.error('고객 로드 실패', error);
    }
}

function searchCustomers() {
    const query = document.getElementById('customer-search').value.toLowerCase();
    const rows = document.querySelectorAll('#customers-list tr');
    rows.forEach(row => {
        const email = row.querySelector('td').textContent.toLowerCase();
        row.style.display = email.includes(query) ? '' : 'none';
    });
}

async function updateUserRole(userId, role) {
    try {
        await fetch(`${API_BASE}/admin/users/${userId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'authorization': `Bearer ${currentToken}`
            },
            body: JSON.stringify({ role })
        });
        showAlert('역할이 변경되었습니다', 'success');
        loadDashboard();
    } catch (error) {
        showAlert('변경 실패', 'error');
    }
}

async function deleteCustomer(userId) {
    if (!confirm('정말 삭제하시겠습니까?')) return;

    try {
        await fetch(`${API_BASE}/admin/users/${userId}`, {
            method: 'DELETE',
            headers: { 'authorization': `Bearer ${currentToken}` }
        });
        showAlert('고객이 삭제되었습니다', 'success');
        loadCustomers();
    } catch (error) {
        showAlert('삭제 실패', 'error');
    }
}

// ===== 대시보드 =====
async function loadDashboard() {
    try {
        const res = await fetch(`${API_BASE}/admin/stats`, {
            headers: { 'authorization': `Bearer ${currentToken}` }
        });

        const data = await res.json();

        document.getElementById('stat-users').textContent = (data.total_users || 0).toLocaleString('ko-KR');
        document.getElementById('stat-revenue').textContent = `₩${(data.total_revenue || 0).toLocaleString('ko-KR')}`;
        document.getElementById('stat-posts').textContent = data.total_posts || 0;
        document.getElementById('stat-keywords').textContent = keywords.length;

        // 결제 통계
        document.getElementById('total-sales').textContent = `₩${(data.total_revenue || 0).toLocaleString('ko-KR')}`;
        document.getElementById('total-transactions').textContent = data.total_transactions || 0;
        document.getElementById('avg-price').textContent = `₩${(data.avg_price || 0).toLocaleString('ko-KR')}`;

        loadPosts();
        loadCustomers();
        loadKeywords();
    } catch (error) {
        console.error('대시보드 로드 실패', error);
    }
}

// ===== 초기화 =====
window.addEventListener('load', () => {
    const token = localStorage.getItem('admin-token');
    if (token) {
        currentToken = token;
        document.getElementById('login-section').style.display = 'none';
        document.getElementById('dashboard-section').style.display = 'block';
        loadDashboard();
    }
});
