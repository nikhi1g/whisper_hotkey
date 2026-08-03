const sourceButton = document.querySelector('[data-source-button]');
const sourceRevision = document.querySelector('[data-source-revision]');
const downloadButton = document.querySelector('[data-download-button]');
const downloadLabel = document.querySelector('[data-download-label]');
const copyOptions = document.querySelectorAll('[data-copy-option]');
const badge = document.querySelector('[data-demo-badge]');
const waveform = badge?.querySelector('.waveform');
const waveformBars = badge?.querySelectorAll('.waveform b') ?? [];
const timer = document.querySelector('[data-demo-timer]');
const stopButton = document.querySelector('[data-demo-stop]');
const sendButton = document.querySelector('[data-demo-send]');
const keySelect = document.querySelector('[data-demo-key]');
const behaviorButtons = [...document.querySelectorAll('[data-demo-behavior]')];
const instruction = document.querySelector('[data-demo-instruction]');
const demoOutput = document.querySelector('[data-demo-output]');
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

document.getElementById('year').textContent = new Date().getFullYear();

const hotkeyChoices = [
  {id: 'right-command', spoken: 'Right Command', holdSupported: true},
  {id: 'left-command', spoken: 'Left Command', holdSupported: true},
  {id: 'right-shift', spoken: 'Right Shift', holdSupported: true},
  {id: 'left-shift', spoken: 'Left Shift', holdSupported: true},
  {id: 'right-option', spoken: 'Right Option', holdSupported: true},
  {id: 'left-option', spoken: 'Left Option', holdSupported: true},
  {id: 'right-control', spoken: 'Right Control', holdSupported: true},
  {id: 'left-control', spoken: 'Left Control', holdSupported: true},
  {id: 'caps-lock', spoken: 'Caps Lock', holdSupported: false},
  {id: 'fn-globe', spoken: 'Fn or Globe', holdSupported: true}
];

const behaviorChoices = [
  {
    id: 'hold',
    name: 'Press and Hold',
    sentence: hotkey => `Hold ${hotkey.spoken}, speak, and release. Your words appear in the field where you are typing.`
  },
  {
    id: 'toggle',
    name: 'Toggle',
    sentence: hotkey => `Tap ${hotkey.spoken} to start, speak, and tap it again. Your words appear in the field where you are typing.`
  },
  {
    id: 'pause',
    name: 'Pause Mode',
    sentence: hotkey => `Tap ${hotkey.spoken} to start, then speak naturally. Your words appear in the field as you pause.`
  }
];

const demoPhrases = [
  'Capture the thought while it is still clear.',
  'Turn the rough idea into a useful first draft.',
  'Write the next step without leaving the keyboard.',
  'Keep your attention on the work in front of you.'
];

const validCombinations = hotkeyChoices.flatMap(hotkey =>
  behaviorChoices
    .filter(behavior => hotkey.holdSupported || behavior.id !== 'hold')
    .map(behavior => ({hotkey, behavior}))
);

let selectedBehaviorID = 'hold';

const delay = (duration, signal) => new Promise((resolve, reject) => {
  if (signal?.aborted) {
    reject(new DOMException('Aborted', 'AbortError'));
    return;
  }

  const finish = () => {
    signal?.removeEventListener('abort', handleAbort);
    resolve();
  };
  const timeout = window.setTimeout(finish, duration);
  const handleAbort = () => {
    window.clearTimeout(timeout);
    reject(new DOMException('Aborted', 'AbortError'));
  };
  signal?.addEventListener('abort', handleAbort, {once: true});
});

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

const refreshStableDownload = async () => {
  if (!downloadButton || !downloadLabel) return;

  try {
    const response = await fetch(
      'https://api.github.com/repos/nikhi1g/whisper_hotkey/releases/latest',
      {headers: {Accept: 'application/vnd.github+json'}}
    );
    if (!response.ok) return;
    const release = await response.json();
    const asset = Array.isArray(release.assets)
      ? release.assets.find(candidate => candidate.name === 'whisper_hotkey.dmg')
      : undefined;
    if (!asset || typeof asset.browser_download_url !== 'string') return;

    downloadButton.href = asset.browser_download_url;
    downloadButton.title = `Download ${release.tag_name}`;
    downloadLabel.textContent = 'Download DMG';
  } catch {
    // The releases page remains a safe fallback until a stable DMG exists.
  }
};

refreshSourceRevision();
refreshStableDownload();
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
      state.textContent = 'Click to copy';
    }, 1600);
  });
});

if (waveformBars.length > 0) {
  const noiseSamples = new Uint32Array(waveformBars.length * 8);

  if (window.crypto?.getRandomValues) {
    window.crypto.getRandomValues(noiseSamples);
  } else {
    noiseSamples.forEach((_, index) => {
      noiseSamples[index] = (index * 2654435761) >>> 0;
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

const selectedHotkey = () => hotkeyChoices.find(choice => choice.id === keySelect?.value) ?? hotkeyChoices[0];
const selectedBehavior = () => behaviorChoices.find(choice => choice.id === selectedBehaviorID) ?? behaviorChoices[0];

const updateInstruction = () => {
  if (!instruction) return;
  instruction.textContent = selectedBehavior().sentence(selectedHotkey());
};

const enforceValidSelection = () => {
  const supportsHold = selectedHotkey().holdSupported;
  if (!supportsHold && selectedBehaviorID === 'hold') selectedBehaviorID = 'toggle';
  behaviorButtons.forEach(button => {
    const isHold = button.dataset.demoBehavior === 'hold';
    const isSelected = button.dataset.demoBehavior === selectedBehaviorID;
    button.disabled = isHold && !supportsHold;
    button.setAttribute('aria-checked', String(isSelected));
  });
};

const setTimer = elapsedMilliseconds => {
  if (!timer) return;
  const totalSeconds = Math.max(0, Math.floor(elapsedMilliseconds / 1000));
  timer.textContent = `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, '0')}`;
};

const replaceOutput = async (text, signal) => {
  if (!demoOutput) return;

  if (prefersReducedMotion || typeof demoOutput.animate !== 'function') {
    demoOutput.textContent = text;
    return;
  }

  const outgoing = demoOutput.animate(
    [{opacity: 1, transform: 'translateY(0)'}, {opacity: 0, transform: 'translateY(-4px)'}],
    {duration: 140, easing: 'ease-in', fill: 'forwards'}
  );
  await outgoing.finished;
  if (signal.aborted) return;
  demoOutput.textContent = text;
  outgoing.cancel();
  const incoming = demoOutput.animate(
    [{opacity: 0, transform: 'translateY(5px)'}, {opacity: 1, transform: 'translateY(0)'}],
    {duration: 260, easing: 'cubic-bezier(.22, 1, .36, 1)'}
  );
  await incoming.finished;
};

let demoController;
let phase = 'idle';
let completeRecording;
let phraseIndex = 1;
let combinationIndex = 0;
let selectionLocked = false;

const setListeningState = () => {
  phase = 'listening';
  badge?.classList.remove('is-transcribing', 'is-displaying');
  badge?.classList.add('is-listening');
  waveform?.classList.remove('is-silent');
  badge?.setAttribute('aria-label', 'Listening. Use Stop and Insert or Send.');
};

const runRecordingPattern = async signal => {
  await delay(1900, signal);
  waveform?.classList.add('is-silent');
  await delay(650, signal);
  waveform?.classList.remove('is-silent');
  await delay(1250, signal);
  return 'send';
};

const runCycle = async signal => {
  updateInstruction();
  setListeningState();
  setTimer(0);

  const recordingStarted = performance.now();
  const timerUpdate = window.setInterval(() => setTimer(performance.now() - recordingStarted), 80);
  const recordingController = new AbortController();
  const stopRecording = () => recordingController.abort();
  signal.addEventListener('abort', stopRecording, {once: true});

  let cycleCompletion;
  const gesture = new Promise(resolve => {
    cycleCompletion = resolve;
    completeRecording = cycleCompletion;
  });
  const pattern = runRecordingPattern(recordingController.signal).catch(error => {
    if (error.name !== 'AbortError') throw error;
    return null;
  });

  const completion = await Promise.race([pattern, gesture]);
  recordingController.abort();
  await pattern;
  signal.removeEventListener('abort', stopRecording);
  if (completeRecording === cycleCompletion) completeRecording = undefined;
  window.clearInterval(timerUpdate);
  setTimer(performance.now() - recordingStarted);
  if (signal.aborted || !completion) return;

  waveform?.classList.remove('is-silent');
  if (completion === 'send') {
    sendButton?.classList.add('is-pressed');
    await delay(180, signal);
    sendButton?.classList.remove('is-pressed');
  } else {
    stopButton?.classList.add('is-pressed');
    await delay(180, signal);
    stopButton?.classList.remove('is-pressed');
  }

  phase = 'transcribing';
  badge?.classList.remove('is-listening');
  badge?.classList.add('is-transcribing');
  badge?.setAttribute('aria-label', 'Transcribing locally.');
  await delay(1380, signal);

  phase = 'inserting';
  await replaceOutput(demoPhrases[phraseIndex], signal);
  phraseIndex = (phraseIndex + 1) % demoPhrases.length;
  badge?.classList.remove('is-transcribing');
  badge?.classList.add('is-displaying');
  badge?.setAttribute('aria-label', 'Dictation inserted.');
  await delay(1250, signal);

  if (!selectionLocked) {
    combinationIndex = (combinationIndex + 1) % validCombinations.length;
    const next = validCombinations[combinationIndex];
    keySelect.value = next.hotkey.id;
    selectedBehaviorID = next.behavior.id;
    enforceValidSelection();
    updateInstruction();
  }
};

const runDemo = async signal => {
  try {
    while (!signal.aborted) {
      await runCycle(signal);
      await delay(700, signal);
    }
  } catch (error) {
    if (error.name !== 'AbortError') throw error;
  }
};

const restartDemo = () => {
  demoController?.abort();
  completeRecording = undefined;
  sendButton?.classList.remove('is-pressed');
  stopButton?.classList.remove('is-pressed');
  enforceValidSelection();
  updateInstruction();
  setTimer(0);

  if (prefersReducedMotion) {
    phase = 'idle';
    badge?.classList.remove('is-transcribing', 'is-displaying');
    badge?.classList.add('is-listening');
    return;
  }

  demoController = new AbortController();
  runDemo(demoController.signal);
};

const handleSelection = () => {
  selectionLocked = true;
  enforceValidSelection();
  restartDemo();
};

keySelect?.addEventListener('change', handleSelection);
behaviorButtons.forEach(button => {
  button.addEventListener('click', () => {
    if (button.disabled) return;
    selectedBehaviorID = button.dataset.demoBehavior;
    handleSelection();
  });
});

sendButton?.addEventListener('click', () => {
  if (prefersReducedMotion) {
    demoOutput.textContent = demoPhrases[phraseIndex];
    phraseIndex = (phraseIndex + 1) % demoPhrases.length;
    return;
  }
  if (phase === 'listening') completeRecording?.('send');
});

stopButton?.addEventListener('click', () => {
  if (prefersReducedMotion) {
    demoOutput.textContent = demoPhrases[phraseIndex];
    phraseIndex = (phraseIndex + 1) % demoPhrases.length;
    return;
  }
  if (phase === 'listening') completeRecording?.('stop');
});

restartDemo();
