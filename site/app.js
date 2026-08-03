const hotkeyHint = document.querySelector('[data-hotkey-cycle]');
const heroSummary = document.querySelector('[data-dictation-copy]');
const sourceButton = document.querySelector('[data-source-button]');
const sourceRevision = document.querySelector('[data-source-revision]');

document.getElementById('year').textContent = new Date().getFullYear();

const hotkeyChoices = [
  {label: 'Right ⌘', spoken: 'Right Command'},
  {label: 'Left ⌘', spoken: 'Left Command'},
  {label: 'Right ⇧', spoken: 'Right Shift'},
  {label: 'Left ⇧', spoken: 'Left Shift'},
  {label: 'Right ⌥', spoken: 'Right Option'},
  {label: 'Left ⌥', spoken: 'Left Option'},
  {label: 'Right ⌃', spoken: 'Right Control'},
  {label: 'Left ⌃', spoken: 'Left Control'},
  {label: 'Caps Lock ⇪', spoken: 'Caps Lock', holdSupported: false},
  {label: 'Fn / Globe', spoken: 'Fn or Globe'}
];

const behaviorChoices = [
  {
    name: 'Press and Hold',
    action: 'hold to talk',
    isAvailable: hotkey => hotkey.holdSupported !== false,
    sentence: hotkey => `Hold ${hotkey.spoken}, speak, and release. Your words appear in the field where you are typing.`
  },
  {
    name: 'Toggle',
    action: 'tap to toggle',
    isAvailable: () => true,
    sentence: hotkey => `Tap ${hotkey.spoken} to start, speak, and tap it again. Your words appear in the field where you are typing.`
  },
  {
    name: 'Pause Mode',
    action: 'pause mode',
    isAvailable: () => true,
    sentence: hotkey => `Tap ${hotkey.spoken} to start, then speak naturally. Your words appear in the field as you pause.`
  }
];

const dictationStates = hotkeyChoices.flatMap(hotkey =>
  behaviorChoices
    .filter(behavior => behavior.isAvailable(hotkey))
    .map(behavior => ({hotkey, behavior, sentence: behavior.sentence(hotkey)}))
);

const wait = duration => new Promise(resolve => window.setTimeout(resolve, duration));

const refreshSourceRevision = async () => {
  if (!sourceButton || !sourceRevision) return;

  try {
    const response = await fetch(`./build.json?t=${Date.now()}`, {cache: 'no-store'});
    if (!response.ok) return;

    const build = await response.json();
    const branchIsValid = typeof build.branch === 'string' && /^[A-Za-z0-9._/-]+$/.test(build.branch);
    const commitIsValid = typeof build.commit === 'string' && /^[0-9a-f]{40}$/i.test(build.commit);
    if (!branchIsValid || !commitIsValid) return;

    const shortCommit = build.commit.slice(0, 7);
    sourceRevision.textContent = `${build.branch}:${shortCommit}`;
    sourceButton.href = `https://github.com/nikhi1g/whisper_hotkey/tree/${build.commit}`;
    sourceButton.title = `View ${build.branch} at ${shortCommit}`;
  } catch {
    // Keep the revision stamped into the deployed HTML when metadata is unavailable.
  }
};

refreshSourceRevision();
window.setInterval(refreshSourceRevision, 30000);

if (hotkeyHint && heroSummary && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const keyLabel = hotkeyHint.querySelector('kbd');
  const actionLabel = hotkeyHint.querySelector('span');
  const visibleCopy = heroSummary.querySelector('[data-visible-copy]');
  const liveCopy = heroSummary.querySelector('[data-live-copy]');
  let stateIndex = 0;

  const typeMinimalReplacement = async nextSentence => {
    const currentSentence = visibleCopy.textContent;
    let sharedLength = 0;

    while (
      sharedLength < currentSentence.length &&
      sharedLength < nextSentence.length &&
      currentSentence[sharedLength] === nextSentence[sharedLength]
    ) {
      sharedLength += 1;
    }

    heroSummary.classList.add('is-typing');

    for (let length = currentSentence.length; length > sharedLength; length -= 1) {
      visibleCopy.textContent = currentSentence.slice(0, length - 1);
      await wait(3);
    }

    for (let length = sharedLength + 1; length <= nextSentence.length; length += 1) {
      visibleCopy.textContent = nextSentence.slice(0, length);
      await wait(8);
    }

    heroSummary.classList.remove('is-typing');
    liveCopy.textContent = nextSentence;
  };

  const showNextState = async () => {
    await wait(2600);
    stateIndex = (stateIndex + 1) % dictationStates.length;
    const state = dictationStates[stateIndex];

    keyLabel.textContent = state.hotkey.label;
    actionLabel.textContent = state.behavior.action;
    hotkeyHint.setAttribute('aria-label', `${state.behavior.name} with ${state.hotkey.spoken}`);
    await typeMinimalReplacement(state.sentence);
    showNextState();
  };

  showNextState();
}
