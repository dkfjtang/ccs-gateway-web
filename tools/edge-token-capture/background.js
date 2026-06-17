chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "GET_COOKIES") {
    return false;
  }

  chrome.cookies.getAll({ url: message.url }, (cookies) => {
    const lastError = chrome.runtime.lastError;
    if (lastError) {
      sendResponse({
        ok: false,
        error: lastError.message,
        cookies: [],
      });
      return;
    }

    sendResponse({
      ok: true,
      cookies: cookies.map((cookie) => ({
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        httpOnly: cookie.httpOnly,
        secure: cookie.secure,
        sameSite: cookie.sameSite,
      })),
    });
  });

  return true;
});
