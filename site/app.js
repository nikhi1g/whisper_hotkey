const hotkeyHint = document.querySelector('[data-hotkey-cycle]');
const heroSummary = document.querySelector('[data-dictation-copy]');
const sourceButton = document.querySelector('[data-source-button]');
const sourceRevision = document.querySelector('[data-source-revision]');
const copyOptions = document.querySelectorAll('[data-copy-option]');
const waveformBars = document.querySelectorAll('.waveform b');

document.getElementById('year').textContent = new Date().getFullYear();

if (waveformBars.length > 0) {
  const noiseSamples = new Uint32Array(waveformBars.length * 8);

  if (window.crypto?.getRandomValues) {
    window.crypto.getRandomValues(noiseSamples);
  } else {
    noiseSamples.forEach((_, index) => {
      noiseSamples[index] = Math.floor(Math.random() * 0xffffffff);
    });
  }

  let noiseIndex = 0;
  const nextNoise = () => noiseSamples[noiseIndex++] / 0xffffffff;
  const level = (minimum, range) => (minimum + nextNoise() * range).toFixed(2);

  waveformBars.forEach(bar => {
    bar.style.setProperty('--wave-a', level(.14, .34));
    bar.style.setProperty('--wave-b', level(.42, .56));
    bar.style.setProperty('--wave-c', level(.18, .48));
    bar.style.setProperty('--wave-d', level(.52, .48));
    bar.style.setProperty('--wave-e', level(.16, .52));
    bar.style.setProperty('--wave-f', level(.38, .57));
    bar.style.setProperty('--wave-duration', `${Math.round(520 + nextNoise() * 680)}ms`);
    bar.style.setProperty('--wave-delay', `${Math.round(-nextNoise() * 1200)}ms`);
  });
}

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

const copyText = async text => {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // Use the local selection fallback below.
    }
  }

  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  const copied = document.execCommand('copy');
  textarea.remove();

  if (!copied) throw new Error('Copy failed');
};

copyOptions.forEach(option => {
  const content = option.querySelector('[data-copy-content]');
  const state = option.querySelector('[data-copy-state]');
  let resetTimer;

  option.addEventListener('click', async () => {
    window.clearTimeout(resetTimer);

    try {
      await copyText(content.textContent.trim());
      state.textContent = 'Copied';
    } catch {
      state.textContent = 'Copy failed';
    }

    resetTimer = window.setTimeout(() => {
      state.textContent = 'Copy';
    }, 1600);
  });
});

if (hotkeyHint && heroSummary && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const keyLabel = hotkeyHint.querySelector('kbd');
  const actionLabel = hotkeyHint.querySelector('span');
  const visibleCopy = heroSummary.querySelector('[data-visible-copy]');
  const liveCopy = heroSummary.querySelector('[data-live-copy]');
  let stateIndex = 0;

  const replaceSentence = async (nextSentence, updateLabels) => {
    if (typeof visibleCopy.animate !== 'function') {
      visibleCopy.textContent = nextSentence;
      liveCopy.textContent = nextSentence;
      updateLabels();
      return;
    }

    const transitionTargets = [visibleCopy, hotkeyHint];
    const outgoing = transitionTargets.map(target => target.animate(
      [{opacity: 1, transform: 'translateY(0)'}, {opacity: 0, transform: 'translateY(-6px)'}],
      {duration: 180, easing: 'cubic-bezier(.4, 0, 1, 1)', fill: 'forwards'}
    ));

    await Promise.all(outgoing.map(animation => animation.finished));

    visibleCopy.textContent = nextSentence;
    liveCopy.textContent = nextSentence;
    updateLabels();
    outgoing.forEach(animation => animation.cancel());

    const incoming = transitionTargets.map(target => target.animate(
      [{opacity: 0, transform: 'translateY(7px)'}, {opacity: 1, transform: 'translateY(0)'}],
      {duration: 280, easing: 'cubic-bezier(.22, 1, .36, 1)'}
    ));

    await Promise.all(incoming.map(animation => animation.finished));
  };

  const showNextState = async () => {
    await wait(6500);
    stateIndex = (stateIndex + 1) % dictationStates.length;
    const state = dictationStates[stateIndex];

    await replaceSentence(state.sentence, () => {
      keyLabel.textContent = state.hotkey.label;
      actionLabel.textContent = state.behavior.action;
      hotkeyHint.setAttribute('aria-label', `${state.behavior.name} with ${state.hotkey.spoken}`);
    });
    showNextState();
  };

  showNextState();
}
