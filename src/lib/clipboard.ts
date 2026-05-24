export async function copyText(text: string): Promise<void> {
  try {
    if (typeof navigator !== "undefined" && navigator.clipboard) {
      await navigator.clipboard.writeText(text);
      return;
    }

    if (typeof document !== "undefined") {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "true");
      textarea.style.position = "fixed";
      textarea.style.top = "-9999px";
      document.body.appendChild(textarea);
      textarea.select();
      const copied = document.execCommand("copy");
      document.body.removeChild(textarea);
      if (copied) {
        return;
      }
    }

    throw new Error("Clipboard copy is not supported");
  } catch (nativeError) {
    throw nativeError instanceof Error
      ? nativeError
      : new Error(String(nativeError));
  }
}
