import './ui.css';

document.body.insertAdjacentHTML('afterbegin', `
<div id="start">
    <div id="meta-tl">PERLIN · 001</div>
    <div id="meta-tr">EVEN FIELD / 3D RAYMARCHER</div>
    <h1 id="title">EVEN<br>FIELD</h1>
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

function hideOverlay() {
    overlay.style.opacity = '0';
    overlay.style.pointerEvents = 'none';
    setTimeout(() => overlay.style.display = 'none', 650);
}

function showOverlay() {
    overlay.style.display = 'flex';
    overlay.style.pointerEvents = '';
    requestAnimationFrame(() => overlay.style.opacity = '1');
}

document.getElementById('enter-btn').addEventListener('click', hideOverlay);

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (overlay.style.display === 'none') showOverlay();
        else hideOverlay();
    }
});
