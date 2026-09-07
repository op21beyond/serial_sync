(() => {
  const textInput = document.getElementById("textInput");
  const voiceSelect = document.getElementById("voiceSelect");
  const speakBtn = document.getElementById("speakBtn");
  const stopBtn = document.getElementById("stopBtn");
  const statusEl = document.getElementById("status");
  const mouth = document.getElementById("mouth");
  const eyeL = document.getElementById("eyeL");
  const eyeR = document.getElementById("eyeR");
  const pupilL = document.getElementById("pupilL");
  const pupilR = document.getElementById("pupilR");

  const synth = window.speechSynthesis;
  let talkTimer = null;
  let blinkTimer = null;

  function setStatus(text) {
    statusEl.textContent = text;
  }

  function supportsSpeech() {
    return "speechSynthesis" in window && "SpeechSynthesisUtterance" in window;
  }

  function populateVoices() {
    if (!supportsSpeech()) return;
    const voices = synth.getVoices();
    voiceSelect.innerHTML = "";

    if (voices.length === 0) {
      const opt = document.createElement("option");
      opt.textContent = "사용 가능한 음성이 없습니다 (브라우저 기본값 사용)";
      opt.value = "";
      voiceSelect.appendChild(opt);
      return;
    }

    const korean = voices.filter((v) => v.lang && v.lang.toLowerCase().startsWith("ko"));
    const others = voices.filter((v) => !korean.includes(v));
    [...korean, ...others].forEach((v, i) => {
      const opt = document.createElement("option");
      opt.value = v.name;
      opt.textContent = `${v.name} (${v.lang})`;
      voiceSelect.appendChild(opt);
    });
  }

  function pickVoice() {
    const voices = synth.getVoices();
    return voices.find((v) => v.name === voiceSelect.value) || null;
  }

  // Idle blinking, independent of speech state.
  function scheduleBlink() {
    const delay = 2500 + Math.random() * 3000;
    blinkTimer = setTimeout(() => {
      eyeL.style.transform = "scaleY(0.1)";
      eyeR.style.transform = "scaleY(0.1)";
      setTimeout(() => {
        eyeL.style.transform = "scaleY(1)";
        eyeR.style.transform = "scaleY(1)";
      }, 120);
      scheduleBlink();
    }, delay);
  }

  function lookAt(dx, dy) {
    pupilL.style.transform = `translate(${dx}px, ${dy}px)`;
    pupilR.style.transform = `translate(${dx}px, ${dy}px)`;
  }

  function openMouth(amount) {
    // amount: 0 (closed) .. 1 (wide open)
    const ry = 4 + amount * 20;
    const cy = 192 + amount * 6;
    mouth.setAttribute("ry", ry.toFixed(1));
    mouth.setAttribute("cy", cy.toFixed(1));
  }

  function startTalkingAnimation() {
    stopTalkingAnimation();
    let open = false;
    talkTimer = setInterval(() => {
      open = !open;
      openMouth(open ? 0.4 + Math.random() * 0.6 : Math.random() * 0.15);
      lookAt((Math.random() - 0.5) * 6, (Math.random() - 0.5) * 4);
    }, 140);
  }

  function pulseMouth() {
    openMouth(0.6 + Math.random() * 0.4);
  }

  function stopTalkingAnimation() {
    if (talkTimer) {
      clearInterval(talkTimer);
      talkTimer = null;
    }
    openMouth(0);
    lookAt(0, 0);
  }

  function setSpeakingUI(isSpeaking) {
    speakBtn.disabled = isSpeaking;
    stopBtn.disabled = !isSpeaking;
  }

  function speak() {
    const text = textInput.value.trim();
    if (!text) {
      setStatus("먼저 텍스트를 입력해주세요.");
      return;
    }
    if (!supportsSpeech()) {
      setStatus("이 브라우저는 음성 합성을 지원하지 않습니다. 애니메이션만 재생합니다.");
      startTalkingAnimation();
      setSpeakingUI(true);
      const estMs = Math.min(8000, 250 * text.split(/\s+/).length);
      setTimeout(() => {
        stopTalkingAnimation();
        setSpeakingUI(false);
        setStatus("");
      }, estMs);
      return;
    }

    synth.cancel();
    const utter = new SpeechSynthesisUtterance(text);
    const voice = pickVoice();
    if (voice) {
      utter.voice = voice;
      utter.lang = voice.lang;
    } else {
      utter.lang = "ko-KR";
    }
    utter.rate = 1.0;
    utter.pitch = 1.05;

    utter.onstart = () => {
      setStatus("말하는 중...");
      setSpeakingUI(true);
      startTalkingAnimation();
    };
    utter.onboundary = () => pulseMouth();
    utter.onend = () => {
      stopTalkingAnimation();
      setSpeakingUI(false);
      setStatus("");
    };
    utter.onerror = (e) => {
      stopTalkingAnimation();
      setSpeakingUI(false);
      setStatus(`음성 재생 중 오류가 발생했습니다: ${e.error || "알 수 없는 오류"}`);
    };

    synth.speak(utter);
  }

  function stop() {
    if (supportsSpeech()) synth.cancel();
    stopTalkingAnimation();
    setSpeakingUI(false);
    setStatus("");
  }

  speakBtn.addEventListener("click", speak);
  stopBtn.addEventListener("click", stop);
  textInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) speak();
  });

  if (supportsSpeech()) {
    populateVoices();
    synth.addEventListener("voiceschanged", populateVoices);
  } else {
    setStatus("이 브라우저는 음성 합성을 지원하지 않습니다. 텍스트를 입력하면 애니메이션만 재생됩니다.");
    voiceSelect.disabled = true;
  }

  openMouth(0);
  scheduleBlink();
})();
