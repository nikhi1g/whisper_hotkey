const repository = 'nikhi1g/whisper_hotkey';
const releasePage = `https://github.com/${repository}/releases/latest`;
const downloadLinks = [...document.querySelectorAll('.js-download')];
const releaseDetail = document.querySelector('.js-release-detail');

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
      link.querySelector('span').textContent = `Download ${release.tag_name}`;
    });
    releaseDetail.textContent = `Apple Silicon · macOS 14+ · ${readableSize(dmg.size)}`;
  } catch {
    downloadLinks.forEach(link => {
      link.href = releasePage;
      link.querySelector('span').textContent = 'View latest release';
    });
    releaseDetail.textContent = 'Apple Silicon · macOS 14+';
  }
};

hydrateRelease();

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
