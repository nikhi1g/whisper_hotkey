const repository = 'nikhi1g/whisper_hotkey';
const previewTag = 'v3.0.8-preview.1';
const previewDownload = `https://github.com/${repository}/releases/download/${previewTag}/whisper_hotkey-preview.dmg`;
const downloadLinks = [...document.querySelectorAll('.js-download')];
const releaseDetail = document.querySelector('.js-release-detail');
const installDetail = document.querySelector('.js-install-detail');
const releaseTrust = [...document.querySelectorAll('.js-release-trust')];
const hotkeyHint = document.querySelector('[data-hotkey-cycle]');

document.getElementById('year').textContent = new Date().getFullYear();

const readableSize = bytes => {
  const megabytes = bytes / (1024 * 1024);
  return `${megabytes >= 1000 ? (megabytes / 1024).toFixed(1) + ' GB' : Math.round(megabytes) + ' MB'}`;
};

const hydrateRelease = async () => {
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      headers: {'Accept': 'application/vnd.github+json'}
    });
    if (!response.ok) throw new Error('Release unavailable');
    const release = await response.json();
    const dmg = release.assets.find(asset => asset.name === 'whisper_hotkey.dmg');
    if (!dmg) throw new Error('DMG unavailable');
    downloadLinks.forEach(link => {
      link.href = dmg.browser_download_url;
      link.querySelector('span').textContent = 'Download for macOS';
    });
    releaseDetail.textContent = `${release.tag_name} · Apple Silicon · macOS 14+ · ${readableSize(dmg.size)}`;
    installDetail.textContent = 'Open the DMG · Drag to Applications · Complete the one-time setup';
    releaseTrust.forEach(element => {
      element.textContent = 'Developer ID signed · Apple notarized · SHA-256 published';
    });
  } catch {
    downloadLinks.forEach(link => {
      link.href = previewDownload;
      link.querySelector('span').textContent = 'Download preview DMG';
    });
    releaseDetail.textContent = `${previewTag} · Apple Silicon · macOS 14+`;
    installDetail.textContent = 'Open the DMG · Drag to Applications · First launch: use Privacy & Security → Open Anyway';
    releaseTrust.forEach(element => {
      element.textContent = 'Preview build · Open Anyway required once · SHA-256 published';
    });
  }
};

hydrateRelease();

const hotkeyChoices = [
  {key: 'Right ⌘', action: 'hold to talk'},
  {key: 'Left ⌘', action: 'hold to talk'},
  {key: 'Right ⇧', action: 'hold to talk'},
  {key: 'Left ⇧', action: 'hold to talk'},
  {key: 'Right ⌥', action: 'hold to talk'},
  {key: 'Left ⌥', action: 'hold to talk'},
  {key: 'Right ⌃', action: 'hold to talk'},
  {key: 'Left ⌃', action: 'hold to talk'},
  {key: 'Caps Lock ⇪', action: 'toggle to talk'},
  {key: 'Fn / Globe', action: 'hold to talk'}
];

if (hotkeyHint && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const keyLabel = hotkeyHint.querySelector('kbd');
  const actionLabel = hotkeyHint.querySelector('span');
  let hotkeyIndex = 0;

  window.setInterval(() => {
    hotkeyHint.classList.add('is-changing');
    window.setTimeout(() => {
      hotkeyIndex = (hotkeyIndex + 1) % hotkeyChoices.length;
      keyLabel.textContent = hotkeyChoices[hotkeyIndex].key;
      actionLabel.textContent = hotkeyChoices[hotkeyIndex].action;
      hotkeyHint.classList.remove('is-changing');
    }, 180);
  }, 2400);
}

if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, {threshold: 0.12});
  document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
} else {
  document.querySelectorAll('.reveal').forEach(element => element.classList.add('visible'));
}
