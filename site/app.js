const hotkeyHint = document.querySelector('[data-hotkey-cycle]');

document.getElementById('year').textContent = new Date().getFullYear();

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
    hotkeyIndex = (hotkeyIndex + 1) % hotkeyChoices.length;
    keyLabel.textContent = hotkeyChoices[hotkeyIndex].key;
    actionLabel.textContent = hotkeyChoices[hotkeyIndex].action;
  }, 2400);
}
