import type { DoorTone, EndingId, UIPrompts } from '../types';

const DEFAULT_SUBTITLE_DURATION_MS = 4500;

const EPILOGUE_BODY: Record<EndingId, string> = {
  calm:
    "Mevrouw De Vos's voice carried down the stairwell, easy as Sunday — 'Just my sister's boy, officer, sleeping off a fever.' Boots turned. A door closed somewhere else. Daniel slept through all of it, his hand still sticky with honey. Someone had opened a door for Sara once, long before this street had a name for what was happening. Tonight, she only had to hold still and trust that the debt would be repaid.",
  nearMiss:
    "Something crashed on the stairs — a pot, a curse, Mevrouw De Vos scolding a soldier for his clumsy boots in her narrow hall. Under the noise of it, Daniel's breath, and Sara's, and nothing else. When the street finally went quiet, Sara realized she had been holding the candle so tightly the wax had cooled between her fingers. Daniel was still warm. That was the only thing that had to be true.",
  costly:
    "The knock came again, softer, and Mevrouw De Vos's voice moved away from their door instead of toward it — down the stairs, out into the snow, drawing the boots after her like a lantern draws moths. Sara heard her laugh at something, too loud, too far down the street. She did not hear her come back. In the room above the shuttered shop, a child slept on, warm, unknowing, alive. Someone had opened a door for Sara once. Tonight she could only wait behind the one Mevrouw De Vos had closed on her way out.",
};

const EPILOGUE_CLOSING_LINE = 'A door had opened for her, once. That is how she knew to hold this one.';

const DOOR_TONE_PROMPT = 'Boots stop outside. A knock. How do you open the door?';

const DOOR_TONE_OPTIONS: Array<{ tone: DoorTone; label: string; title: string }> = [
  { tone: 'warm', label: 'Warm', title: 'greet her like an old friend' },
  { tone: 'silent', label: 'Silent', title: 'open it without a word' },
  { tone: 'indignant', label: 'Indignant', title: 'meet suspicion with defiance' },
];

function requireElement<T extends HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`UIPrompts: missing #${id} in DOM`);
  return el as T;
}

export function createUIPrompts(): UIPrompts {
  const interactPrompt = requireElement<HTMLElement>('interact-prompt');
  const subtitle = requireElement<HTMLElement>('subtitle');
  const choicePanel = requireElement<HTMLElement>('choice-panel');
  const choicePromptEl = requireElement<HTMLElement>('choice-prompt');
  const choiceButtons = requireElement<HTMLElement>('choice-buttons');
  const epilogueOverlay = requireElement<HTMLElement>('overlay-epilogue');
  const epilogueText = requireElement<HTMLElement>('epilogue-text');

  let subtitleTimer: ReturnType<typeof window.setTimeout> | undefined;

  function showInteractPrompt(label: string): void {
    interactPrompt.textContent = label;
    interactPrompt.classList.remove('hidden');
  }

  function hideInteractPrompt(): void {
    interactPrompt.classList.add('hidden');
  }

  function clearSubtitleTimer(): void {
    if (subtitleTimer !== undefined) {
      window.clearTimeout(subtitleTimer);
      subtitleTimer = undefined;
    }
  }

  function showSubtitle(text: string, durationMs: number = DEFAULT_SUBTITLE_DURATION_MS): void {
    clearSubtitleTimer();
    subtitle.textContent = text;
    subtitle.classList.remove('hidden');
    if (durationMs > 0) {
      subtitleTimer = window.setTimeout(hideSubtitle, durationMs);
    }
  }

  function hideSubtitle(): void {
    clearSubtitleTimer();
    subtitle.classList.add('hidden');
  }

  function hideDoorToneChoice(): void {
    choicePanel.classList.add('hidden');
  }

  function showDoorToneChoice(onChoose: (tone: DoorTone) => void): void {
    choicePromptEl.textContent = DOOR_TONE_PROMPT;
    choiceButtons.innerHTML = '';

    let firstButton: HTMLButtonElement | null = null;
    for (const option of DOOR_TONE_OPTIONS) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = option.label;
      button.title = option.title;
      button.setAttribute('aria-label', option.title);
      button.addEventListener('click', () => {
        hideDoorToneChoice();
        onChoose(option.tone);
      });
      choiceButtons.appendChild(button);
      if (!firstButton) firstButton = button;
    }

    choicePanel.classList.remove('hidden');
    firstButton?.focus();
  }

  function showEpilogue(ending: EndingId): void {
    epilogueText.textContent = `${EPILOGUE_BODY[ending]} ${EPILOGUE_CLOSING_LINE}`;
    epilogueOverlay.classList.remove('hidden');
  }

  return {
    showInteractPrompt,
    hideInteractPrompt,
    showSubtitle,
    hideSubtitle,
    showDoorToneChoice,
    hideDoorToneChoice,
    showEpilogue,
  };
}
