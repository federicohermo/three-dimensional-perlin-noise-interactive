import './ui.css';

document.body.insertAdjacentHTML('afterbegin', `
<div id="start">
    <div id="meta-tl">PERLIN · 001</div>
    <div id="meta-tr">SDF DEMO / 3D RAYMARCHER</div>
    <h1 id="title">SDF<br>DEMO</h1>
    <nav id="controls">
        <span>WASD — MOVE</span>
        <span>SPACE — JUMP</span>
        <span>DRAG — LOOK</span>
        <span>E — ATTACH SPHERE</span>
        <span>Q — DETACH SPHERE</span>
    </nav>
    <div id="bottom-bar">
        <div id="rule"></div>
        <button id="enter-btn">ENTER</button>
    </div>
</div>
`);

const overlay = document.getElementById('start');
const btn = document.getElementById('enter-btn');

// Disabled until shaders are compiled
btn.textContent = 'LOADING...';
btn.disabled = true;

export function hideOverlay() {
    overlay.style.opacity = '0';
    overlay.style.pointerEvents = 'none';
    setTimeout(() => overlay.style.display = 'none', 650);
}

function showOverlay() {
    overlay.style.display = 'flex';
    overlay.style.pointerEvents = '';
    requestAnimationFrame(() => overlay.style.opacity = '1');
}

export function setReady() {
    btn.textContent = 'ENTER';
    btn.disabled = false;
}

export function onEnter() {
    return new Promise(resolve => btn.addEventListener('click', resolve, { once: true }));
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (overlay.style.display === 'none') showOverlay();
        else hideOverlay();
    }
});
