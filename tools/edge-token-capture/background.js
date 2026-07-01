import { isAllowedCcsUrl } from "./url-policy.js";

const ccsSessionCookieName = "cc-switch-session";

function isPopupSender(sender) {
  try {
    const senderUrl = new URL(sender?.url || "");
    return (
      senderUrl.origin === `chrome-extension://${chrome.runtime.id}` &&
      senderUrl.pathname === "/popup.html"
    );
  } catch {
    return false;
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "GET_CCS_SESSION") {
    if (!isPopupSender(_sender)) {
      sendResponse({
        ok: false,
        error: "仅允许从扩展弹窗读取 CCS 登录态。",
        value: null,
      });
      return false;
    }

    if (!isAllowedCcsUrl(message.url)) {
      sendResponse({
        ok: false,
        error: "CCS 登录态只能从本地 http(s) 或非本地 https 服务读取。",
        value: null,
      });
      return false;
    }

    chrome.cookies.get(
      { url: message.url, name: ccsSessionCookieName },
      (cookie) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) {
          sendResponse({
            ok: false,
            error: lastError.message,
            value: null,
          });
          return;
        }

        sendResponse({
          ok: true,
          value: cookie?.value || null,
        });
      },
    );
    return true;
  }

  if (message?.type !== "GET_COOKIES") {
    return false;
  }

  if (!isPopupSender(_sender)) {
    sendResponse({
      ok: false,
      error: "仅允许从扩展弹窗读取 Cookie。",
      cookies: [],
    });
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
