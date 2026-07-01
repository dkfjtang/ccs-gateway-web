import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { authVaultApi, type AuthVaultReceiveWindowStatus } from "@/lib/api";

function formatRemaining(seconds: number | null | undefined) {
  const value = Math.max(0, seconds ?? 0);
  const minutes = Math.floor(value / 60);
  const rest = value % 60;
  return `${minutes}:${String(rest).padStart(2, "0")}`;
}

function deriveStatus(
  status: AuthVaultReceiveWindowStatus | null,
  tick: number,
) {
  if (!status?.enabled || !status.expiresAt) {
    return status?.remainingSeconds ?? 0;
  }

  const expiresAt = new Date(status.expiresAt).getTime();
  if (!Number.isFinite(expiresAt)) {
    return status.remainingSeconds ?? 0;
  }

  return Math.max(0, Math.ceil((expiresAt - tick) / 1000));
}

export function AuthVaultReceiveWindowSection() {
  const { t } = useTranslation();
  const [status, setStatus] = useState<AuthVaultReceiveWindowStatus | null>(
    null,
  );
  const [isBusy, setIsBusy] = useState(false);
  const [tick, setTick] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setTick(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const remainingSeconds = useMemo(
    () => deriveStatus(status, tick),
    [status, tick],
  );
  const isOpen = Boolean(status?.enabled && remainingSeconds > 0);

  useEffect(() => {
    if (status?.enabled && remainingSeconds <= 0) {
      setStatus({
        ...status,
        enabled: false,
        status: "closed",
        remainingSeconds: 0,
        closedReason: "expired",
      });
    }
  }, [remainingSeconds, status]);

  const handleToggle = async (checked: boolean) => {
    setIsBusy(true);
    try {
      const next = checked
        ? await authVaultApi.openReceiveWindow()
        : await authVaultApi.closeReceiveWindow();
      setStatus(next);
      toast.success(
        checked
          ? t("settings.advanced.authVaultReceive.openSuccess")
          : t("settings.advanced.authVaultReceive.closeSuccess"),
        { closeButton: true },
      );
    } catch (error) {
      toast.error(
        error instanceof Error
          ? error.message
          : t("settings.advanced.authVaultReceive.requestFailed"),
      );
    } finally {
      setIsBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="space-y-1">
          <Label className="flex items-center gap-2">
            <ShieldCheck className="h-4 w-4 text-primary" />
            {t("settings.advanced.authVaultReceive.switchLabel")}
          </Label>
          <p className="text-xs text-muted-foreground">
            {t("settings.advanced.authVaultReceive.switchDescription")}
          </p>
        </div>
        <Switch
          checked={isOpen}
          disabled={isBusy}
          onCheckedChange={handleToggle}
          aria-label={t("settings.advanced.authVaultReceive.switchLabel")}
        />
      </div>

      <div className="grid gap-3 rounded-lg bg-muted/50 p-4 text-xs text-muted-foreground sm:grid-cols-3">
        <div>
          <p className="font-medium text-foreground">
            {isOpen
              ? t("settings.advanced.authVaultReceive.statusOpen")
              : t("settings.advanced.authVaultReceive.statusClosed")}
          </p>
          <p>{t("settings.advanced.authVaultReceive.statusLabel")}</p>
        </div>
        <div>
          <p className="font-mono font-medium text-foreground">
            {formatRemaining(remainingSeconds)}
          </p>
          <p>{t("settings.advanced.authVaultReceive.remainingLabel")}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">
            {status?.failureCount ?? 0}/5
          </p>
          <p>{t("settings.advanced.authVaultReceive.failureLabel")}</p>
        </div>
      </div>
    </div>
  );
}
