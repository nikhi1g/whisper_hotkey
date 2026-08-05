const sourceButton = document.querySelector('[data-source-button]');
const sourceRevision = document.querySelector('[data-source-revision]');
const downloadButton = document.querySelector('[data-download-button]');
const downloadLabel = document.querySelector('[data-download-label]');
const downloadVersion = document.querySelector('[data-download-version]');
const copyOptions = document.querySelectorAll('[data-copy-option]');
const badge = document.querySelector('[data-demo-badge]');
const activityTrail = badge?.querySelector('.activity-trail path');
const waveform = badge?.querySelector('.waveform');
const waveformBars = badge?.querySelectorAll('.waveform b') ?? [];
const timer = document.querySelector('[data-demo-timer]');
const stopButton = document.querySelector('[data-demo-stop]');
const sendButton = document.querySelector('[data-demo-send]');
const keyPicker = document.querySelector('[data-key-picker]');
const keyTrigger = document.querySelector('[data-demo-key]');
const keyLabel = document.querySelector('[data-demo-key-label]');
const keyMenu = document.querySelector('[data-demo-key-options]');
const keyOptions = [...document.querySelectorAll('[data-hotkey-option]')];
const behaviorButtons = [...document.querySelectorAll('[data-demo-behavior]')];
const instruction = document.querySelector('[data-demo-instruction]');
const demoOutput = document.querySelector('[data-demo-output]');
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const demoTiming = Object.freeze({
  speechLead: 1900,
  speechPause: 650,
  speechTail: 1250,
  controlPress: 180,
  transcriptionLap: 1110,
  incomingText: 260
});
const demoTrailDuration = demoTiming.transcriptionLap;
badge?.style.setProperty('--demo-trail-duration', `${demoTrailDuration}ms`);

document.getElementById('year').textContent = new Date().getFullYear();

const hotkeyChoices = [
  {id: 'right-option', spoken: 'Right Option', holdSupported: true},
  {id: 'right-command', spoken: 'Right Command', holdSupported: true},
  {id: 'left-command', spoken: 'Left Command', holdSupported: true},
  {id: 'right-shift', spoken: 'Right Shift', holdSupported: true},
  {id: 'left-shift', spoken: 'Left Shift', holdSupported: true},
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
let selectedHotkeyID = 'right-option';

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

const waitForTrailCompletion = signal => {
  if (signal?.aborted) return Promise.reject(new DOMException('Aborted', 'AbortError'));
  if (prefersReducedMotion || !activityTrail) return delay(1, signal);

  return new Promise((resolve, reject) => {
    const cleanup = () => {
      activityTrail.removeEventListener('animationend', handleAnimationEnd);
      signal?.removeEventListener('abort', handleAbort);
    };
    const handleAnimationEnd = event => {
      if (event.animationName !== 'trail-flow') return;
      cleanup();
      badge?.classList.add('is-trail-complete');
      resolve();
    };
    const handleAbort = () => {
      cleanup();
      reject(new DOMException('Aborted', 'AbortError'));
    };
    activityTrail.addEventListener('animationend', handleAnimationEnd);
    signal?.addEventListener('abort', handleAbort, {once: true});
  });
};

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
    sourceButton.href = 'https://github.com/nikhi1g/whisper_hotkey/tree/main';
    sourceButton.title = `View main. Current site build ${shortCommit}`;
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
    const assets = Array.isArray(release.assets) ? release.assets : [];
    // The ZIP is the human download. macOS blocks an unnotarized disk image
    // before it mounts, so the DMG is only the fallback for older releases.
    const asset =
      assets.find(candidate => candidate.name === 'whisper_hotkey.zip') ??
      assets.find(candidate => candidate.name === 'whisper_hotkey.dmg');
    if (!asset || typeof asset.browser_download_url !== 'string') return;

    downloadButton.href = asset.browser_download_url;
    downloadButton.title = `Download ${release.tag_name}`;
    downloadLabel.textContent = 'Download for macOS';
    if (downloadVersion && typeof release.tag_name === 'string') {
      downloadVersion.textContent = release.tag_name;
    }
  } catch {
    // The releases page remains a safe fallback until a stable build exists.
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

const selectedHotkey = () => hotkeyChoices.find(choice => choice.id === selectedHotkeyID) ?? hotkeyChoices[0];
const selectedBehavior = () => behaviorChoices.find(choice => choice.id === selectedBehaviorID) ?? behaviorChoices[0];

const syncKeyPicker = () => {
  const selectedOption = keyOptions.find(option => option.dataset.hotkeyOption === selectedHotkeyID);
  if (keyLabel && selectedOption) keyLabel.textContent = selectedOption.textContent.trim();
  keyOptions.forEach(option => {
    option.setAttribute('aria-selected', String(option.dataset.hotkeyOption === selectedHotkeyID));
  });
};

const focusKeyOption = index => {
  if (keyOptions.length === 0) return;
  keyOptions[(index + keyOptions.length) % keyOptions.length].focus();
};

const openKeyMenu = direction => {
  if (!keyMenu || !keyTrigger) return;
  selectionLocked = true;
  keyMenu.hidden = false;
  keyTrigger.setAttribute('aria-expanded', 'true');
  const selectedIndex = Math.max(0, keyOptions.findIndex(option => option.dataset.hotkeyOption === selectedHotkeyID));
  window.requestAnimationFrame(() => focusKeyOption(selectedIndex + direction));
};

const closeKeyMenu = returnFocus => {
  if (!keyMenu || !keyTrigger) return;
  keyMenu.hidden = true;
  keyTrigger.setAttribute('aria-expanded', 'false');
  if (returnFocus) keyTrigger.focus();
};

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

  demoOutput.textContent = text;

  if (prefersReducedMotion || typeof demoOutput.animate !== 'function') {
    return;
  }

  const incoming = demoOutput.animate(
    [{opacity: .25, transform: 'translateY(5px)'}, {opacity: 1, transform: 'translateY(0)'}],
    {duration: demoTiming.incomingText, easing: 'cubic-bezier(.22, 1, .36, 1)'}
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
  if (badge) {
    badge.classList.remove(
      'is-transcribing',
      'is-displaying',
      'is-cycle-progress',
      'is-trail-complete'
    );
    badge.classList.add('is-listening');
  }
  waveform?.classList.remove('is-silent');
  badge?.setAttribute('aria-label', 'Listening. Use Stop and Insert or Send.');
};

const runRecordingPattern = async signal => {
  await delay(demoTiming.speechLead, signal);
  waveform?.classList.add('is-silent');
  await delay(demoTiming.speechPause, signal);
  waveform?.classList.remove('is-silent');
  await delay(demoTiming.speechTail, signal);
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
    await delay(demoTiming.controlPress, signal);
    sendButton?.classList.remove('is-pressed');
  } else {
    stopButton?.classList.add('is-pressed');
    await delay(demoTiming.controlPress, signal);
    stopButton?.classList.remove('is-pressed');
  }

  phase = 'transcribing';
  badge?.classList.remove('is-listening', 'is-trail-complete', 'is-cycle-progress');
  if (badge) void badge.offsetWidth;
  const trailCompletion = waitForTrailCompletion(signal);
  badge?.classList.add('is-transcribing', 'is-cycle-progress');
  badge?.setAttribute('aria-label', 'Transcribing locally.');
  await trailCompletion;

  phase = 'inserting';
  badge?.classList.remove('is-transcribing', 'is-cycle-progress', 'is-trail-complete');
  badge?.classList.add('is-displaying');
  badge?.setAttribute('aria-label', 'Dictation inserted.');
  await replaceOutput(demoPhrases[phraseIndex], signal);
  phraseIndex = (phraseIndex + 1) % demoPhrases.length;
  await delay(1250, signal);

  if (!selectionLocked) {
    combinationIndex = (combinationIndex + 1) % validCombinations.length;
    const next = validCombinations[combinationIndex];
    selectedHotkeyID = next.hotkey.id;
    selectedBehaviorID = next.behavior.id;
    syncKeyPicker();
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
  badge?.classList.remove('is-cycle-progress');
  badge?.classList.remove('is-trail-complete');
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

keyTrigger?.addEventListener('click', () => {
  if (keyMenu?.hidden) openKeyMenu(0);
  else closeKeyMenu(false);
});

keyTrigger?.addEventListener('keydown', event => {
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    openKeyMenu(event.key === 'ArrowDown' ? 0 : -1);
  }
});

keyOptions.forEach((option, index) => {
  option.addEventListener('click', () => {
    selectedHotkeyID = option.dataset.hotkeyOption;
    syncKeyPicker();
    closeKeyMenu(true);
    handleSelection();
  });

  option.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      focusKeyOption(index + (event.key === 'ArrowDown' ? 1 : -1));
    } else if (event.key === 'Home' || event.key === 'End') {
      event.preventDefault();
      focusKeyOption(event.key === 'Home' ? 0 : keyOptions.length - 1);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      option.click();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      closeKeyMenu(true);
    } else if (event.key === 'Tab') {
      closeKeyMenu(false);
    }
  });
});

document.addEventListener('pointerdown', event => {
  if (!keyPicker?.contains(event.target)) closeKeyMenu(false);
});

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

syncKeyPicker();
restartDemo();
