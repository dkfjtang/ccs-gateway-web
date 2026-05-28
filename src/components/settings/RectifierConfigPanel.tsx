import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  settingsApi,
  type RectifierConfig,
  type OptimizerConfig,
} from "@/lib/api/settings";

const DEFAULT_OPTIMIZER_CONFIG: OptimizerConfig = {
  enabled: false,
  thinkingOptimizer: true,
  cacheInjection: true,
  cacheTtl: "1h",
  tokenSaver: false,
  tokenSaverMinChars: 4000,
  tokenSaverKeepChars: 800,
  cavemanOutputCompression: false,
  passthroughServiceTier: true,
};

function normalizeOptimizerConfig(config: OptimizerConfig): OptimizerConfig {
  const tokenSaverMinChars = Math.max(160, config.tokenSaverMinChars);
  const tokenSaverKeepChars = Math.min(
    Math.max(80, config.tokenSaverKeepChars),
    tokenSaverMinChars - 1,
  );

  return {
    ...config,
    tokenSaverMinChars,
    tokenSaverKeepChars,
  };
}

export function RectifierConfigPanel() {
  const { t } = useTranslation();
  const [config, setConfig] = useState<RectifierConfig>({
    enabled: true,
    requestThinkingSignature: true,
    requestThinkingBudget: true,
  });
  const [optimizerConfig, setOptimizerConfig] = useState<OptimizerConfig>(
    DEFAULT_OPTIMIZER_CONFIG,
  );
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadConfigs = async () => {
      try {
        const [rectifier, optimizer] = await Promise.all([
          settingsApi.getRectifierConfig(),
          settingsApi.getOptimizerConfig(),
        ]);
        setConfig(rectifier);
        setOptimizerConfig(
          normalizeOptimizerConfig({ ...DEFAULT_OPTIMIZER_CONFIG, ...optimizer }),
        );
      } catch (e) {
        console.error("Failed to load rectifier/optimizer config:", e);
      } finally {
        setIsLoading(false);
      }
    };

    void loadConfigs();
  }, []);

  const handleChange = async (updates: Partial<RectifierConfig>) => {
    const newConfig = { ...config, ...updates };
    setConfig(newConfig);
    try {
      await settingsApi.setRectifierConfig(newConfig);
    } catch (e) {
      console.error("Failed to save rectifier config:", e);
      toast.error(String(e));
      setConfig(config);
    }
  };

  const handleOptimizerChange = async (updates: Partial<OptimizerConfig>) => {
    const newConfig = normalizeOptimizerConfig({ ...optimizerConfig, ...updates });
    setOptimizerConfig(newConfig);
    try {
      await settingsApi.setOptimizerConfig(newConfig);
    } catch (e) {
      console.error("Failed to save optimizer config:", e);
      toast.error(String(e));
      setOptimizerConfig(optimizerConfig);
    }
  };

  if (isLoading) return null;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-0.5">
          <Label>{t("settings.advanced.rectifier.enabled")}</Label>
          <p className="text-xs text-muted-foreground">
            {t("settings.advanced.rectifier.enabledDescription")}
          </p>
        </div>
        <Switch
          checked={config.enabled}
          onCheckedChange={(checked) => handleChange({ enabled: checked })}
        />
      </div>

      <div className="space-y-4">
        <h4 className="text-sm font-medium text-muted-foreground">
          {t("settings.advanced.rectifier.requestGroup")}
        </h4>
        <div className="flex items-center justify-between pl-4">
          <div className="space-y-0.5">
            <Label>{t("settings.advanced.rectifier.thinkingSignature")}</Label>
            <p className="text-xs text-muted-foreground">
              {t("settings.advanced.rectifier.thinkingSignatureDescription")}
            </p>
          </div>
          <Switch
            checked={config.requestThinkingSignature}
            disabled={!config.enabled}
            onCheckedChange={(checked) =>
              handleChange({ requestThinkingSignature: checked })
            }
          />
        </div>
        <div className="flex items-center justify-between pl-4">
          <div className="space-y-0.5">
            <Label>{t("settings.advanced.rectifier.thinkingBudget")}</Label>
            <p className="text-xs text-muted-foreground">
              {t("settings.advanced.rectifier.thinkingBudgetDescription")}
            </p>
          </div>
          <Switch
            checked={config.requestThinkingBudget}
            disabled={!config.enabled}
            onCheckedChange={(checked) =>
              handleChange({ requestThinkingBudget: checked })
            }
          />
        </div>
      </div>

      <div className="border-t pt-6 mt-6">
        <div className="space-y-1 mb-4">
          <h3 className="text-sm font-medium">
            {t("settings.advanced.optimizer.title")}
          </h3>
          <p className="text-xs text-muted-foreground">
            {t("settings.advanced.optimizer.description")}
          </p>
        </div>

        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label>{t("settings.advanced.optimizer.enabled")}</Label>
            </div>
            <Switch
              checked={optimizerConfig.enabled}
              onCheckedChange={(checked) =>
                handleOptimizerChange({ enabled: checked })
              }
            />
          </div>

          <div className="space-y-4 pl-4">
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>
                  {t("settings.advanced.optimizer.thinkingOptimizer")}
                </Label>
                <p className="text-xs text-muted-foreground">
                  {t(
                    "settings.advanced.optimizer.thinkingOptimizerDescription",
                  )}
                </p>
              </div>
              <Switch
                checked={optimizerConfig.thinkingOptimizer}
                disabled={!optimizerConfig.enabled}
                onCheckedChange={(checked) =>
                  handleOptimizerChange({ thinkingOptimizer: checked })
                }
              />
            </div>

            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>{t("settings.advanced.optimizer.cacheInjection")}</Label>
                <p className="text-xs text-muted-foreground">
                  {t("settings.advanced.optimizer.cacheInjectionDescription")}
                </p>
              </div>
              <Switch
                checked={optimizerConfig.cacheInjection}
                disabled={!optimizerConfig.enabled}
                onCheckedChange={(checked) =>
                  handleOptimizerChange({ cacheInjection: checked })
                }
              />
            </div>

            {optimizerConfig.cacheInjection && (
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>{t("settings.advanced.optimizer.cacheTtl")}</Label>
                </div>
                <select
                  className="h-9 rounded-md border border-input bg-background px-3 text-sm"
                  value={optimizerConfig.cacheTtl}
                  disabled={
                    !optimizerConfig.enabled || !optimizerConfig.cacheInjection
                  }
                  onChange={(e) =>
                    handleOptimizerChange({
                      cacheTtl: e.target.value as OptimizerConfig["cacheTtl"],
                    })
                  }
                >
                  <option value="5m">
                    {t("settings.advanced.optimizer.cacheTtl5m")}
                  </option>
                  <option value="1h">
                    {t("settings.advanced.optimizer.cacheTtl1h")}
                  </option>
                </select>
              </div>
            )}

            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>{t("settings.advanced.optimizer.tokenSaver")}</Label>
                <p className="text-xs text-muted-foreground">
                  {t("settings.advanced.optimizer.tokenSaverDescription")}
                </p>
              </div>
              <Switch
                checked={optimizerConfig.tokenSaver}
                disabled={!optimizerConfig.enabled}
                onCheckedChange={(checked) =>
                  handleOptimizerChange({ tokenSaver: checked })
                }
              />
            </div>

            {optimizerConfig.tokenSaver && (
              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>{t("settings.advanced.optimizer.tokenSaverMinChars")}</span>
                  <input
                    className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground"
                    type="number"
                    min={160}
                    value={optimizerConfig.tokenSaverMinChars}
                    disabled={!optimizerConfig.enabled || !optimizerConfig.tokenSaver}
                    onChange={(e) =>
                      handleOptimizerChange({
                        tokenSaverMinChars: Math.max(160, Number(e.target.value) || 4000),
                      })
                    }
                  />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>{t("settings.advanced.optimizer.tokenSaverKeepChars")}</span>
                  <input
                    className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground"
                    type="number"
                    min={80}
                    value={optimizerConfig.tokenSaverKeepChars}
                    disabled={!optimizerConfig.enabled || !optimizerConfig.tokenSaver}
                    onChange={(e) =>
                      handleOptimizerChange({
                        tokenSaverKeepChars: Math.max(80, Number(e.target.value) || 800),
                      })
                    }
                  />
                </label>
              </div>
            )}

            <div className="flex items-center justify-between rounded-lg border border-border/50 p-3">
              <div className="space-y-0.5">
                <Label>{t("settings.advanced.optimizer.passthroughServiceTier")}</Label>
                <p className="text-xs text-muted-foreground">
                  {t("settings.advanced.optimizer.passthroughServiceTierDescription")}
                </p>
              </div>
              <Switch
                checked={optimizerConfig.passthroughServiceTier}
                onCheckedChange={(checked) =>
                  handleOptimizerChange({ passthroughServiceTier: checked })
                }
              />
            </div>

            <div className="rounded-md border border-dashed p-3 opacity-75">
              <Label>{t("settings.advanced.optimizer.cavemanOutputCompression")}</Label>
              <p className="mt-1 text-xs text-muted-foreground">
                {t("settings.advanced.optimizer.cavemanOutputCompressionDescription")}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
