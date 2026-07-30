// ============================================
// NJU Auto Auth Login - Content Script
// Injected into authserver.nju.edu.cn/authserver/login
// ============================================

(async function () {
  'use strict';

  let sliderInteractionStarted = false;
  const markSliderLoginSubmitted = () => {
    if (sliderInteractionStarted) {
      sessionStorage.setItem('nju_slider_login_submitted', '1');
    }
  };
  document.addEventListener('submit', () => {
    markSliderLoginSubmitted();
  }, true);
  const nativeFormSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function (...args) {
    markSliderLoginSubmitted();
    return nativeFormSubmit.apply(this, args);
  };

  // --- Helpers ---
  function log(msg, level = 'info') {
    console.log(`[NJU Auto Auth][${level}] ${msg}`);
    chrome.runtime.sendMessage({ action: 'contentLog', msg, level }).catch(() => {});
  }

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }


  function getLoginErrorText() {
    const errorTip = document.querySelector('.login-main #showErrorTip');
    return errorTip ? errorTip.textContent.trim() : '';
  }

  async function waitForLoginOutcome(timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (!window.location.href.includes('authserver/login')) {
        return { success: true };
      }
      const errorText = getLoginErrorText();
      if (errorText) return { errorText };
      await sleep(100);
    }
    return { timedOut: true };
  }

  function isElementVisible(element) {
    if (!element || !element.isConnected) return false;
    const style = window.getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' &&
           Number(style.opacity || 1) !== 0 && element.getClientRects().length > 0;
  }
  function getSliderElements() {
    const root = document.querySelector('#sliderCaptchaDiv');
    if (!root || !isElementVisible(root)) return null;

    const slider = root.querySelector('.slider');
    const sliderContainer = root.querySelector('.sliderContainer');
    const blockCanvas = root.querySelector('canvas.block');
    const backgroundCanvas = root.querySelector('#sliderDiv > canvas:not(.block)') ||
                             root.querySelector('canvas:not(.block)');
    if (!slider || !sliderContainer || !blockCanvas || !backgroundCanvas) return null;
    return { root, slider, sliderContainer, blockCanvas, backgroundCanvas };
  }

  async function waitForSliderElements(timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const elements = getSliderElements();
      if (elements && elements.blockCanvas.width > 0 && elements.blockCanvas.height > 0) {
        try {
          const pixels = elements.blockCanvas.getContext('2d').getImageData(
            0, 0, elements.blockCanvas.width, elements.blockCanvas.height
          ).data;
          for (let i = 3; i < pixels.length; i += 4) {
            if (pixels[i] > 32) return elements;
          }
        } catch (e) {
          // The canvas may still be initializing; retry until the timeout.
        }
      }
      await sleep(100);
    }
    return null;
  }

  function getCanvasFingerprint(canvas) {
    try {
      const width = canvas.width;
      const height = canvas.height;
      const pixels = canvas.getContext('2d', { willReadFrequently: true })
        .getImageData(0, 0, width, height).data;
      let hash = 2166136261;
      const columns = 24;
      const rows = 16;
      for (let row = 0; row < rows; row++) {
        const y = Math.min(height - 1, Math.floor((row + 0.5) * height / rows));
        for (let column = 0; column < columns; column++) {
          const x = Math.min(width - 1, Math.floor((column + 0.5) * width / columns));
          const index = (y * width + x) * 4;
          for (let channel = 0; channel < 4; channel++) {
            hash ^= pixels[index + channel];
            hash = Math.imul(hash, 16777619);
          }
        }
      }
      return `${width}x${height}:${hash >>> 0}`;
    } catch (error) {
      return null;
    }
  }

  function getSliderChallengeFingerprint(elements) {
    if (!elements) return null;
    const background = getCanvasFingerprint(elements.backgroundCanvas);
    const block = getCanvasFingerprint(elements.blockCanvas);
    return background && block ? `${background}|${block}` : null;
  }

  async function waitForSliderChallengeRefresh(previousFingerprint, previousElements, timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const current = getSliderElements();
      if (current) {
        const fingerprint = getSliderChallengeFingerprint(current);
        if (current.root !== previousElements?.root ||
            current.blockCanvas !== previousElements?.blockCanvas ||
            (fingerprint && fingerprint !== previousFingerprint)) {
          return true;
        }
      }
      await sleep(50);
    }
    return false;
  }

  function findSliderTarget(elements, debugDetails = null) {
    const { blockCanvas, backgroundCanvas } = elements;
    const width = backgroundCanvas.width;
    const height = backgroundCanvas.height;
    const backgroundContext = backgroundCanvas.getContext('2d', { willReadFrequently: true });
    const background = backgroundContext.getImageData(0, 0, width, height).data;
    const blockContext = blockCanvas.getContext('2d', { willReadFrequently: true });
    const blockWidth = blockCanvas.width;
    const blockHeight = blockCanvas.height;
    const block = blockContext.getImageData(0, 0, blockWidth, blockHeight).data;
    const boundaryPixels = [];
    const interiorPixels = [];
    const directions = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    const alphaAt = (x, y) => {
      if (x < 0 || x >= blockWidth || y < 0 || y >= blockHeight) return 0;
      return block[(y * blockWidth + x) * 4 + 3];
    };
    const gradientAt = (x, y) => {
      const luminanceAt = (sampleX, sampleY) => {
        const index = (sampleY * width + sampleX) * 4;
        return background[index] * 0.299 +
               background[index + 1] * 0.587 +
               background[index + 2] * 0.114;
      };
      return Math.abs(luminanceAt(x + 1, y) - luminanceAt(x - 1, y)) +
             Math.abs(luminanceAt(x, y + 1) - luminanceAt(x, y - 1));
    };

    // A real gap has a strong puzzle-shaped edge but relatively little texture
    // inside it. Penalizing interior gradients prevents natural image edges
    // (buildings, text, etc.) from winning on edge strength alone.
    for (let y = 2; y < Math.min(height, blockHeight) - 2; y++) {
      for (let x = 2; x < blockWidth - 2; x++) {
        const alpha = alphaAt(x, y);
        const isInterior = alpha > 245 && directions.every(
          ([dx, dy]) => alphaAt(x + dx, y + dy) > 220
        );
        if (isInterior) {
          if ((x + y) % 3 === 0) interiorPixels.push({ x, y });
          continue;
        }
        if (alpha >= 128 && directions.some(
          ([dx, dy]) => alphaAt(x + dx, y + dy) < 32
        )) {
          boundaryPixels.push({ x, y });
        }
      }
    }

    if (boundaryPixels.length < 12 || interiorPixels.length < 12) {
      throw new Error('Unable to read slider puzzle outline');
    }

    const maxBlockX = boundaryPixels.reduce((max, pixel) => Math.max(max, pixel.x), 0);
    let bestLeft = -1;
    let bestScore = -Infinity;
    for (let left = 1; left + maxBlockX < width - 1; left++) {
      let edgeGradient = 0;
      let interiorGradient = 0;
      for (const pixel of boundaryPixels) {
        edgeGradient += gradientAt(left + pixel.x, pixel.y);
      }
      for (const pixel of interiorPixels) {
        interiorGradient += gradientAt(left + pixel.x, pixel.y);
      }
      const edgeMean = edgeGradient / boundaryPixels.length;
      const interiorMean = interiorGradient / interiorPixels.length;
      const score = edgeMean - interiorMean * 0.8;
      if (score > bestScore) {
        bestScore = score;
        bestLeft = left;
      }
    }

    if (bestLeft < 0) throw new Error('Unable to locate the slider target');
    if (debugDetails) {
      Object.assign(debugDetails, {
        backgroundWidth: width,
        backgroundHeight: height,
        blockWidth,
        blockHeight,
        boundaryPixelCount: boundaryPixels.length,
        interiorPixelCount: interiorPixels.length,
        maxBlockX,
        candidateCount: Math.max(0, width - maxBlockX - 2),
        bestScore,
        bestLeft
      });
    }
    return bestLeft;
  }

  const sliderTrajectoryFiles = ['3.json'];
  const sliderTrajectoryIntervalMs = 2;
  const sliderTrajectoryMaxPointsPerFrame = 24;

  function pickSliderTrajectoryFile() {
    return sliderTrajectoryFiles[Math.floor(Math.random() * sliderTrajectoryFiles.length)];
  }

  async function loadSliderTrajectory() {
    const filename = pickSliderTrajectoryFile();
    const response = await fetch(chrome.runtime.getURL(`recordings/${filename}`));
    if (!response.ok) throw new Error(`Unable to load slider trajectory ${filename}`);

    const points = (await response.json()).filter(point =>
      Number.isFinite(point?.x) && Number.isFinite(point?.y)
    );
    if (points.length < 2 || Math.abs(points.at(-1).x - points[0].x) < 1) {
      throw new Error(`Invalid slider trajectory ${filename}`);
    }
    return { filename, points };
  }

  function captureSliderCanvas(canvas) {
    if (!canvas) return null;
    try {
      return canvas.toDataURL('image/png');
    } catch (error) {
      return null;
    }
  }

  async function recordSliderDebugAttempt(payload) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const response = await chrome.runtime.sendMessage({
          action: 'recordSliderCaptchaDebug',
          ...payload
        });
        if (response?.error) throw new Error(response.error);
        return true;
      } catch (error) {
        if (attempt === 2) {
          console.error('[NJU Auto Auth][debug] Failed to record slider attempt:', error);
          return false;
        }
        await sleep(25);
      }
    }
    return false;
  }

  function scaleSliderTrajectory(points, dragDistance, sliderTravel) {
    const first = points[0];
    const last = points.at(-1);
    const horizontalScale = dragDistance / (last.x - first.x);
    const maxVerticalOffset = points.reduce(
      (maximum, point) => Math.max(maximum, Math.abs(point.y - first.y)),
      0
    );
    const verticalScale = maxVerticalOffset > 0 ? Math.min(1, 7 / maxVerticalOffset) : 1;
    const maxX = Math.max(0, sliderTravel - 1);

    const scaledPoints = points.map(point => ({
      x: Math.max(0, Math.min(maxX, (point.x - first.x) * horizontalScale)),
      y: (point.y - first.y) * verticalScale
    }));
    const xs = points.map(point => point.x);
    const ys = points.map(point => point.y);

    return {
      points: scaledPoints,
      metadata: {
        horizontalScale,
        verticalScale,
        maxVerticalOffset,
        rawStart: first,
        rawEnd: last,
        rawBounds: {
          minX: Math.min(...xs),
          maxX: Math.max(...xs),
          minY: Math.min(...ys),
          maxY: Math.max(...ys)
        }
      }
    };
  }

  async function dragSlider(elements, targetLeft, attempt) {
    const { slider, sliderContainer, backgroundCanvas } = elements;
    const sliderRect = slider.getBoundingClientRect();
    const containerWidth = sliderContainer.getBoundingClientRect().width || backgroundCanvas.width + 2;
    const sliderWidth = sliderRect.width || 40;
    const sliderTravel = containerWidth - sliderWidth;
    // NJU's customized Longbow 2.0 moves the handle and puzzle block 1:1.
    const correction = 0;
    const dragDistance = Math.max(2, Math.min(
      sliderTravel - 1,
      targetLeft + correction
    ));
    const startX = sliderRect.left + sliderWidth / 2;
    const startY = sliderRect.top + (sliderRect.height || 40) / 2;
    const trajectoryLoadStartedAt = performance.now();
    const recorded = await loadSliderTrajectory();
    const scaled = scaleSliderTrajectory(recorded.points, dragDistance, sliderTravel);
    const trajectory = scaled.points;
    const trajectoryLoadAndScaleMs = performance.now() - trajectoryLoadStartedAt;

    sliderInteractionStarted = true;
    slider.dispatchEvent(new MouseEvent('mousedown', {
      bubbles: true, cancelable: true, clientX: startX, clientY: startY, buttons: 1
    }));


    const requestedDurationMs = (trajectory.length - 1) * sliderTrajectoryIntervalMs;
    log(`Using slider trajectory ${recorded.filename} (${trajectory.length} raw points, ${sliderTrajectoryIntervalMs}ms/point)`);

    // Preserve the 1ms trajectory timeline without flooding the task queue.
    // Each animation frame dispatches due points with a safety cap, leaving the
    // browser one rendering opportunity per frame and avoiding catch-up bursts.
    const playbackStartedAt = performance.now();
    await new Promise(resolve => {
      let lastDispatchedIndex = 0;
      const playFrame = now => {
        const elapsed = now - playbackStartedAt;
        const targetIndex = Math.min(
          trajectory.length - 1,
          lastDispatchedIndex + sliderTrajectoryMaxPointsPerFrame,
          Math.floor(elapsed / sliderTrajectoryIntervalMs)
        );
        while (lastDispatchedIndex < targetIndex) {
          lastDispatchedIndex += 1;
          const point = trajectory[lastDispatchedIndex];
          document.dispatchEvent(new MouseEvent('mousemove', {
            bubbles: true,
            cancelable: true,
            clientX: startX + point.x,
            clientY: startY + point.y,
            buttons: 1
          }));
        }
        if (lastDispatchedIndex < trajectory.length - 1) requestAnimationFrame(playFrame);
        else resolve();
      };
      requestAnimationFrame(playFrame);
    });

    const finalPoint = trajectory.at(-1);
    document.dispatchEvent(new MouseEvent('mouseup', {
      bubbles: true,
      cancelable: true,
      clientX: startX + finalPoint.x,
      clientY: startY + finalPoint.y,
      buttons: 0
    }));
    const actualPlaybackDurationMs = performance.now() - playbackStartedAt;

    return {
      attempt,
      filename: recorded.filename,
      rawPointCount: recorded.points.length,
      rawPoints: recorded.points,
      scaledPoints: trajectory,
      pointIntervalMs: sliderTrajectoryIntervalMs,
      scheduler: 'requestAnimationFrame-batched',
      maxPointsPerFrame: sliderTrajectoryMaxPointsPerFrame,
      requestedDurationMs,
      actualPlaybackDurationMs,
      actualAveragePointIntervalMs: actualPlaybackDurationMs / (trajectory.length - 1),
      trajectoryLoadAndScaleMs,
      targetLeft,
      correction,
      dragDistance,
      sliderTravel,
      sliderWidth,
      containerWidth,
      startClientPoint: { x: startX, y: startY },
      finalOffset: finalPoint,
      ...scaled.metadata
    };
  }

  async function solveSliderCaptcha(maxAttempts = 2) {
    const debugState = await chrome.storage.local.get('nju_debug_mode');
    const sliderDebugEnabled = debugState.nju_debug_mode === true;
    let previousChallengeFingerprint = null;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const attemptStartedAt = Date.now();
      const performanceStartedAt = performance.now();
      const timings = {};
      let elements = null;
      let challengeFingerprint = null;
      let imageData = '';
      let canvasDetails = null;
      let targetLeft = null;
      let detectionAlgorithmDetails = {};
      let trajectoryDetails = null;
      let stage = '等待滑块画布';
      let outcome = { type: 'unknown', message: '尚未得到校验结果' };
      const debugRecordId = sliderDebugEnabled ? crypto.randomUUID() : null;
      let debugFinalized = false;

      const writeDebugRecord = async (status, error = '') => {
        if (!sliderDebugEnabled || debugFinalized) return;
        timings.totalAttemptMs = performance.now() - performanceStartedAt;
        const saved = await recordSliderDebugAttempt({
          recordId: debugRecordId,
          status,
          imageData,
          result: status === 'success' ? {
            targetLeft,
            dragDistance: trajectoryDetails?.dragDistance,
            trajectoryFile: trajectoryDetails?.filename,
            pointCount: trajectoryDetails?.rawPointCount,
            outcome: outcome.type
          } : null,
          error,
          startedAt: attemptStartedAt,
          context: {
            attempt,
            maxAttempts,
            challengeFingerprint,
            pageUrl: window.location.href
          },
          debugDetails: {
            schemaVersion: 1,
            stage,
            canvas: canvasDetails,
            detection: targetLeft == null ? null : {
              ...detectionAlgorithmDetails,
              targetLeft,
              correction: trajectoryDetails?.correction ?? 0,
              dragDistance: trajectoryDetails?.dragDistance,
              sliderTravel: trajectoryDetails?.sliderTravel
            },
            trajectory: trajectoryDetails,
            timings,
            outcome
          }
        });
        if (saved && status !== 'pending') debugFinalized = true;
      };

      try {
        const existingErrorText = getLoginErrorText();
        if (existingErrorText && !existingErrorText.includes('验证码')) {
          throw new Error('NJU_INVALID_CREDENTIALS');
        }
        log(`Starting slider attempt ${attempt}...`);
        const elementsStartedAt = performance.now();
        elements = await waitForSliderElements(5000);
        timings.elementsReadyMs = performance.now() - elementsStartedAt;
        if (!elements) throw new Error('Timed out while loading slider captcha');

        challengeFingerprint = getSliderChallengeFingerprint(elements);
        if (previousChallengeFingerprint && challengeFingerprint === previousChallengeFingerprint) {
          stage = '等待新验证码';
          const duplicateWaitStartedAt = performance.now();
          const refreshed = await waitForSliderChallengeRefresh(
            previousChallengeFingerprint,
            elements,
            5000
          );
          timings.duplicateChallengeWaitMs = performance.now() - duplicateWaitStartedAt;
          if (!refreshed) throw new Error('Slider captcha did not refresh after the previous attempt');
          elements = await waitForSliderElements(5000);
          challengeFingerprint = getSliderChallengeFingerprint(elements);
          if (!elements || !challengeFingerprint || challengeFingerprint === previousChallengeFingerprint) {
            throw new Error('Refusing to retry the same slider captcha');
          }
        }
        previousChallengeFingerprint = challengeFingerprint;

        if (sliderDebugEnabled) {
          const captureStartedAt = performance.now();
          const backgroundRect = elements.backgroundCanvas.getBoundingClientRect();
          const blockRect = elements.blockCanvas.getBoundingClientRect();
          imageData = captureSliderCanvas(elements.backgroundCanvas) || '';
          canvasDetails = {
            background: {
              width: elements.backgroundCanvas.width,
              height: elements.backgroundCanvas.height,
              cssWidth: backgroundRect.width,
              cssHeight: backgroundRect.height
            },
            block: {
              width: elements.blockCanvas.width,
              height: elements.blockCanvas.height,
              cssWidth: blockRect.width,
              cssHeight: blockRect.height,
              imageData: captureSliderCanvas(elements.blockCanvas)
            },
            sliderContainerWidth: elements.sliderContainer.getBoundingClientRect().width
          };
          timings.canvasCaptureMs = performance.now() - captureStartedAt;
        }

        stage = '定位拼图缺口';
        const detectionStartedAt = performance.now();
        targetLeft = findSliderTarget(
          elements,
          sliderDebugEnabled ? detectionAlgorithmDetails : null
        );
        timings.targetDetectionMs = performance.now() - detectionStartedAt;
        log(`Slider target located at ${targetLeft}px`);

        stage = '加载并播放轨迹';
        trajectoryDetails = await dragSlider(elements, targetLeft, attempt);
        timings.trajectoryLoadAndScaleMs = trajectoryDetails.trajectoryLoadAndScaleMs;
        timings.trajectoryPlaybackMs = trajectoryDetails.actualPlaybackDurationMs;

        stage = '滑动已完成';
        outcome = { type: 'dispatched', message: 'mouseup 已派发，等待校验结果' };
        await writeDebugRecord('pending');

        stage = '滑动后等待';
        const postDragDelayStartedAt = performance.now();
        await sleep(50);
        timings.postDragDelayMs = performance.now() - postDragDelayStartedAt;

        stage = '等待滑块校验结果';
        const verificationStartedAt = performance.now();
        const deadline = Date.now() + 2500;
        while (Date.now() < deadline) {
          if (!window.location.href.includes('authserver/login')) {
            timings.verificationWaitMs = performance.now() - verificationStartedAt;
            stage = '校验成功';
            outcome = { type: 'redirect', message: '页面已离开统一身份认证登录页' };
            await writeDebugRecord('success');
            return true;
          }
          if (elements.sliderContainer.classList.contains('sliderContainer_success')) {
            timings.verificationWaitMs = performance.now() - verificationStartedAt;
            stage = '校验成功';
            outcome = { type: 'success-class', message: '检测到 sliderContainer_success' };
            await writeDebugRecord('success');
            log('Slider verified; waiting for login submission...');
            const loginOutcome = await waitForLoginOutcome(6000);
            if (loginOutcome.success) return true;
            throw new Error('NJU_INVALID_CREDENTIALS');
          }
          if (elements.sliderContainer.classList.contains('sliderContainer_fail')) {
            timings.verificationWaitMs = performance.now() - verificationStartedAt;
            stage = '校验失败';
            outcome = { type: 'failure-class', message: '检测到 sliderContainer_fail' };
            break;
          }
          const errorText = getLoginErrorText();
          if (errorText) {
            if (errorText.includes('验证码')) {
              timings.verificationWaitMs = performance.now() - verificationStartedAt;
              stage = '校验失败';
              outcome = { type: 'captcha-error', message: errorText };
              break;
            }
            throw new Error('NJU_INVALID_CREDENTIALS');
          }
          await sleep(100);
        }

        if (timings.verificationWaitMs == null) {
          timings.verificationWaitMs = performance.now() - verificationStartedAt;
          stage = '校验超时';
          outcome = { type: 'timeout', message: '2.5 秒内未观察到成功或失败状态' };
        }
        await writeDebugRecord('error', outcome.message);
      } catch (error) {
        stage = stage === '校验成功' ? stage : '执行异常';
        outcome = { type: 'exception', message: error.message || String(error) };
        await writeDebugRecord('error', outcome.message);
        if (error.message === 'NJU_INVALID_CREDENTIALS') throw error;
        if (attempt >= maxAttempts) {
          throw new Error('NJU_SLIDER_FAILED_TWICE');
        }
      }

      if (attempt < maxAttempts) {
        log('Slider verification failed; retrying immediately...', 'warn');
      }
    }
    throw new Error('NJU_SLIDER_FAILED_TWICE');
  }

  async function submitLoginAndSolveSlider(loginViewDiv) {
    const loginBtn = loginViewDiv.querySelector('#login_submit');
    if (!loginBtn) throw new Error('Login button not found');

    log('Credentials filled; submitting login...');
    loginBtn.click();

    const deadline = Date.now() + 6000;
    while (Date.now() < deadline) {
      if (!window.location.href.includes('authserver/login')) return true;
      if (getSliderElements()) {
        log('Slider captcha appeared after submit; solving...');
        return solveSliderCaptcha();
      }
      const errorText = getLoginErrorText();
      if (errorText && !errorText.includes('验证码')) {
        throw new Error('NJU_INVALID_CREDENTIALS');
      }
      await sleep(100);
    }
    throw new Error('Slider captcha did not appear after login submission');
  }

  function waitForElement(selector, container, timeoutMs = 10000) {
    return new Promise((resolve, reject) => {
      const el = container.querySelector(selector);
      if (el) {
        resolve(el);
        return;
      }

      const observer = new MutationObserver(() => {
        const el = container.querySelector(selector);
        if (el) {
          observer.disconnect();
          resolve(el);
        }
      });

      observer.observe(container, { childList: true, subtree: true });

      setTimeout(() => {
        observer.disconnect();
        const el = container.querySelector(selector);
        if (el) {
          resolve(el);
        } else {
          reject(new Error(`等待元素 ${selector} 超时`));
        }
      }, timeoutMs);
    });
  }

  // --- Check if we should auto-login ---
  const data = await chrome.storage.local.get([
    'nju_auto_login_pending', 'nju_username', 'nju_password',
    'nju_auth_auto_login', 'nju_page_auto_login'
  ]);

  const isPending = data.nju_auto_login_pending;
  const authAutoLoginEnabled = data.nju_auth_auto_login ?? data.nju_page_auto_login === true;
  const isPageLogin = !isPending && authAutoLoginEnabled;

  if (!isPending && !isPageLogin) {
    // Not triggered by our extension and auto-login not enabled, do nothing
    return;
  }

  const username = data.nju_username;
  const password = data.nju_password;

  if (!username || !password) {
    if (isPending) {
      log('用户名或密码未配置', 'error');
      notifyLoginResult(false, '用户名或密码未配置');
    }
    // If it's a page-visit trigger, silently skip — user hasn't configured credentials
    return;
  }

  if (isPageLogin) {
    log('检测到用户打开了登录页面，自动登录已启用，开始自动填充...');
  } else {
    log('内容脚本已注入，开始自动登录流程...');
  }

  try {
    await performAutoLogin(username, password);
  } catch (err) {
    log(`自动登录异常: ${err.message}`, 'error');
    if (isPending) {
      notifyLoginResult(false, err.message);
    }
  }

  // =============================================
  // Main auto-login logic
  // =============================================
  async function performAutoLogin(username, password) {
    // Step 1: Wait for the login container to exist
    log('等待登录容器加载...');
    const loginViewDiv = await waitForElement('#loginViewDiv', document.body, 10000);

    // Check if password login is already active
    let usernameField = loginViewDiv.querySelector('.m-account #username');
    if (!usernameField) {
      // Need to switch to password login tab
      log('切换到账号登录标签...');
      const pwdLoginLink = await waitForElement('#userNameLogin_a', document.body, 5000).catch(() => null);
      if (pwdLoginLink) {
        pwdLoginLink.click();
        // Wait for the form to appear inside loginViewDiv
        try {
          usernameField = await waitForElement('#username', loginViewDiv, 3000);
        } catch(e) {}
      }

      if (!usernameField) {
        usernameField = loginViewDiv.querySelector('.m-account #username') || loginViewDiv.querySelector('#username');
      }
      if (!usernameField) {
        throw new Error('找不到用户名输入框');
      }
    }

    // Step 3: Fill username and password in the same turn.
    log('并行填写用户名和密码...');
    const passwordField = loginViewDiv.querySelector('.m-account #password') ||
                          loginViewDiv.querySelector('#password');
    if (!passwordField) {
      throw new Error('找不到密码输入框');
    }

    usernameField.removeAttribute('readonly');
    passwordField.removeAttribute('readonly');
    setNativeValue(usernameField, username);
    setNativeValue(passwordField, password);
    usernameField.dispatchEvent(new Event('input', { bubbles: true }));
    usernameField.dispatchEvent(new Event('change', { bubbles: true }));
    passwordField.dispatchEvent(new Event('input', { bubbles: true }));
    passwordField.dispatchEvent(new Event('change', { bubbles: true }));
    usernameField.dispatchEvent(new Event('focusout', { bubbles: true }));
    usernameField.dispatchEvent(new Event('blur', { bubbles: true }));

    await submitLoginAndSolveSlider(loginViewDiv);
    log('登录成功！', 'success');
    notifyLoginResult(true, '', isPageLogin);
  }

  // =============================================
  // Utility functions
  // =============================================

  function setNativeValue(element, value) {
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value'
    ).set;
    nativeInputValueSetter.call(element, value);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function notifyLoginResult(success, message = '', userInitiated = false) {
    chrome.runtime.sendMessage({
      action: 'loginComplete',
      success,
      message,
      userInitiated,
      tabId: null // Background will get tabId from sender
    }).catch(() => {});
  }

  // --- Monitor page navigation for login result ---
  // If the page navigates away from login, it means success
  const originalUrl = window.location.href;
  const navigationObserver = new MutationObserver(() => {
    if (!window.location.href.includes('authserver/login') && 
        window.location.href !== originalUrl) {
      log('页面已跳转，登录成功！', 'success');
      notifyLoginResult(true, '', isPageLogin);
    }
  });

  // Also listen for beforeunload as a signal
  window.addEventListener('beforeunload', () => {
    // If we're navigating away from login page, it likely means success
    if (window.location.href !== originalUrl) {
      notifyLoginResult(true, '', isPageLogin);
    }
  });

})();
