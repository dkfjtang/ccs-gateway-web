/**
 * Custom User-Agent validity check.
 *
 * Keep this aligned with the backend `parse_custom_user_agent`, which uses
 * `http::HeaderValue::from_str`: empty after trim means unset; control
 * characters except tab are invalid.
 */
export function isValidUserAgentHeader(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed === "") return true;
  // eslint-disable-next-line no-control-regex
  return !/[\x00-\x08\x0a-\x1f\x7f]/.test(trimmed);
}
