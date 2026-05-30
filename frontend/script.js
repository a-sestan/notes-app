const API_BASE = ''; // Postavi na ALB URL za produkciju, npr. 'http://<alb-dns>/api'


let notes = [];
let activeTag = null;
let activeColor = 0;
let activeFilter = 'sve';
let searchQ = '';
let sortMode = 'new';
let editingId = null;

async function fetchNotes() {
  try {
    const res = await fetch(API_BASE + '/api/notes');
    const data = await res.json();
    
    notes = data.map(n => ({
      ...n,
      ts: new Date(n.created_at).getTime()
    }));
    
    render();
  } catch (err) {
    console.error('Greška pri učitavanju bilješki:', err);
  }
}

function fmtTime(ts) {
  const diff = (Date.now() - ts) / 1000;
  if (diff < 60) return 'Upravo sada';
  if (diff < 3600) return Math.floor(diff / 60) + 'm';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h';
  return new Date(ts).toLocaleDateString('bs', { day: 'numeric', month: 'short' });
}

function esc(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function addNote() {
  const title = document.getElementById('inp-title').value.trim();
  const content = document.getElementById('inp-content').value.trim();
  if (!title) { document.getElementById('inp-title').focus(); return; }

  const newNote = {
    title: title,
    content: content,
    tag: activeTag,
    color: activeColor,
    pinned: false
  };

  try {
    await fetch(API_BASE + '/api/notes', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newNote)
    });

    document.getElementById('inp-title').value = '';
    document.getElementById('inp-content').value = '';
    document.getElementById('char-count').textContent = '0 znakova';
    activeTag = null;
    activeColor = 0;
    document.querySelectorAll('.tag-pill').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.color-dot').forEach((d, i) => d.classList.toggle('selected', i === 0));
    
    fetchNotes();
  } catch (err) {
    console.error('Greška pri dodavanju:', err);
  }
}

async function togglePin(id) {
  try {
    await fetch(API_BASE + `/api/notes/${id}/pin`, { method: 'PATCH' });
    fetchNotes(); 
  } catch (err) {
    console.error('Greška pri pinovanju:', err);
  }
}

async function deleteNote(id) {
  if (!confirm('Obrisati ovu bilješku?')) return;
  
  try {
    await fetch(API_BASE + `/api/notes/${id}`, { method: 'DELETE' });
    fetchNotes(); // Osvježi listu
  } catch (err) {
    console.error('Greška pri brisanju:', err);
  }
}

function openEdit(id) {
  editingId = id;
  const n = notes.find(x => x.id === id);
  document.getElementById('edit-text').value = n.content || '';
  document.getElementById('edit-title-display').textContent = n.title;
  document.getElementById('edit-modal').classList.add('open');
}

function closeModal() {
  document.getElementById('edit-modal').classList.remove('open');
}

async function saveEdit() {
  const n = notes.find(x => x.id === editingId);
  if (n) {
    const updatedContent = document.getElementById('edit-text').value;
    
    const updatedNote = {
      title: n.title,
      content: updatedContent,
      tag: n.tag,
      color: n.color,
      pinned: n.pinned
    };

    try {
      await fetch(API_BASE + `/api/notes/${editingId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatedNote)
      });
      fetchNotes(); // Osvježi listu
    } catch (err) {
      console.error('Greška pri ažuriranju:', err);
    }
  }
  closeModal();
}

function render() {
  let list = [...notes];

  if (activeFilter === 'pinned') list = list.filter(n => n.pinned);
  else if (activeFilter !== 'sve') list = list.filter(n => n.tag === activeFilter);

  if (searchQ) {
    list = list.filter(n =>
      (n.title + (n.content || '')).toLowerCase().includes(searchQ.toLowerCase())
    );
  }

  if (sortMode === 'new')  list.sort((a, b) => (b.pinned - a.pinned) || (b.ts - a.ts));
  if (sortMode === 'old')  list.sort((a, b) => (b.pinned - a.pinned) || (a.ts - b.ts));
  if (sortMode === 'az')   list.sort((a, b) => (b.pinned - a.pinned) || a.title.localeCompare(b.title));
  if (sortMode === 'len')  list.sort((a, b) => (b.pinned - a.pinned) || ((b.content || '').length - (a.content || '').length));

  const weekAgo = Date.now() - 7 * 86400 * 1000;
  document.getElementById('s-total').textContent = notes.length;
  document.getElementById('s-pinned').textContent = notes.filter(n => n.pinned).length;
  document.getElementById('s-week').textContent = notes.filter(n => n.ts > weekAgo).length;
  document.getElementById('s-chars').textContent = notes.reduce((a, n) => a + (n.content || '').length, 0);

  const el = document.getElementById('notes-list');

  if (!list.length) {
    el.innerHTML = '<div class="empty"><div class="empty-icon">✨</div>Nema bilješki — dodaj prvu!</div>';
    return;
  }

  el.innerHTML = list.map(n => `
    <div class="note-card card-color-${n.color || 0}${n.pinned ? ' pinned' : ''}">
      <div class="card-top">
        <div class="note-title">${esc(n.title)}</div>
        <div class="note-actions">
          <button class="action-btn" onclick="openEdit(${n.id})" title="Uredi">✏️</button>
          <button class="action-btn" onclick="togglePin(${n.id})" title="${n.pinned ? 'Otkači' : 'Zakači'}">📌</button>
          <button class="action-btn del" onclick="deleteNote(${n.id})" title="Obriši">✕</button>
        </div>
      </div>
      <div class="note-body">
        ${esc(n.content) || '<span class="note-empty">Bez sadržaja</span>'}
      </div>
      <div class="note-footer">
        <div class="note-footer-left">
          ${n.tag ? `<span class="note-tag tag-${n.tag}">${n.tag}</span>` : ''}
          ${n.pinned ? '<span class="pin-badge">zakačena</span>' : ''}
        </div>
        <div class="note-meta">
          ${n.content ? `<span class="note-chars">${n.content.length} znakova</span>` : ''}
          <span class="note-time">${fmtTime(n.ts)}</span>
        </div>
      </div>
    </div>
  `).join('');
}

// Event listeneri ostaju potpuno isti kao što si ih napisao
document.getElementById('filters').addEventListener('click', e => {
  const btn = e.target.closest('.filter-btn');
  if (!btn) return;
  activeFilter = btn.dataset.filter;
  document.querySelectorAll('.filter-btn').forEach(b => b.classList.toggle('active', b === btn));
  render();
});

document.getElementById('tag-picker').addEventListener('click', e => {
  const btn = e.target.closest('.tag-pill');
  if (!btn) return;
  if (activeTag === btn.dataset.tag) {
    activeTag = null;
    btn.classList.remove('active');
  } else {
    document.querySelectorAll('.tag-pill').forEach(p => p.classList.remove('active'));
    activeTag = btn.dataset.tag;
    btn.classList.add('active');
  }
});

document.getElementById('color-picker').addEventListener('click', e => {
  const dot = e.target.closest('.color-dot');
  if (!dot) return;
  activeColor = parseInt(dot.dataset.c);
  document.querySelectorAll('.color-dot').forEach(d => d.classList.toggle('selected', d === dot));
});

document.getElementById('search').addEventListener('input', e => {
  searchQ = e.target.value;
  render();
});

document.getElementById('sort-sel').addEventListener('change', e => {
  sortMode = e.target.value;
  render();
});

document.getElementById('inp-content').addEventListener('input', e => {
  document.getElementById('char-count').textContent = e.target.value.length + ' znakova';
});

document.getElementById('inp-title').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); document.getElementById('inp-content').focus(); }
});

document.getElementById('inp-content').addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.ctrlKey) addNote();
});

document.getElementById('edit-modal').addEventListener('click', e => {
  if (e.target === document.getElementById('edit-modal')) closeModal();
});

fetchNotes();