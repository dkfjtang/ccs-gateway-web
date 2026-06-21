import { useTranslation } from "react-i18next";
import { useState, useEffect } from "react";
import {
  ChevronDown,
  ChevronRight,
  FlaskConical,
  Coins,
  Wrench,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { ProviderTestConfig } from "@/types";

export type PricingModelSourceOption = "inherit" | "request" | "response";

interface ProviderPricingConfig {
  enabled: boolean;
  costMultiplier?: string;
  pricingModelSource: PricingModelSourceOption;
}

interface ProviderAdvancedConfigProps {
  testConfig: ProviderTestConfig;
  pricingConfig: ProviderPricingConfig;
  omitMaxOutputTokens: boolean;
  requireResponsesInstructions: boolean;
  disableImageGeneration: boolean;
  omitMaxOutputTokensAvailable: boolean;
  disableImageGenerationAvailable: boolean;
  onTestConfigChange: (config: ProviderTestConfig) => void;
  onPricingConfigChange: (config: ProviderPricingConfig) => void;
  onOmitMaxOutputTokensChange: (enabled: boolean) => void;
  onRequireResponsesInstructionsChange: (enabled: boolean) => void;
  onDisableImageGenerationChange: (enabled: boolean) => void;
}

export function ProviderAdvancedConfig({
  testConfig,
  pricingConfig,
  omitMaxOutputTokens,
  requireResponsesInstructions,
  disableImageGeneration,
  omitMaxOutputTokensAvailable,
  disableImageGenerationAvailable,
  onTestConfigChange,
  onPricingConfigChange,
  onOmitMaxOutputTokensChange,
  onRequireResponsesInstructionsChange,
  onDisableImageGenerationChange,
}: ProviderAdvancedConfigProps) {
  const { t } = useTranslation();
  const [isCompatibilityConfigOpen, setIsCompatibilityConfigOpen] = useState(
    omitMaxOutputTokens ||
      requireResponsesInstructions ||
      (disableImageGenerationAvailable && disableImageGeneration),
  );
  const [isTestConfigOpen, setIsTestConfigOpen] = useState(testConfig.enabled);
  const [isPricingConfigOpen, setIsPricingConfigOpen] = useState(
    pricingConfig.enabled,
  );

  const shouldShowCompatibilityConfig =
    omitMaxOutputTokensAvailable ||
    omitMaxOutputTokens ||
    requireResponsesInstructions ||
    disableImageGenerationAvailable;

  useEffect(() => {
    if (
      omitMaxOutputTokens ||
      requireResponsesInstructions ||
      (disableImageGenerationAvailable && disableImageGeneration)
    ) {
      setIsCompatibilityConfigOpen(true);
    }
  }, [
    omitMaxOutputTokens,
    requireResponsesInstructions,
    disableImageGeneration,
    disableImageGenerationAvailable,
  ]);

  useEffect(() => {
    setIsTestConfigOpen(testConfig.enabled);
  }, [testConfig.enabled]);

  useEffect(() => {
    setIsPricingConfigOpen(pricingConfig.enabled);
  }, [pricingConfig.enabled]);

  return (
    <div className="space-y-4">
      {shouldShowCompatibilityConfig && (
        <div className="rounded-lg border border-border/50 bg-muted/20">
          <button
            type="button"
            className="flex w-full items-center justify-between p-4 hover:bg-muted/30 transition-colors"
            aria-expanded={isCompatibilityConfigOpen}
            aria-controls="provider-compatibility-config"
            onClick={() =>
              setIsCompatibilityConfigOpen(!isCompatibilityConfigOpen)
            }
          >
            <div className="flex items-center gap-3">
              <Wrench className="h-4 w-4 text-muted-foreground" />
              <span className="font-medium">
                {t("providerAdvanced.compatibilityConfig", {
                  defaultValue: "兼容性选项",
                })}
              </span>
            </div>
            <div className="flex items-center gap-3">
              {(omitMaxOutputTokens ||
                requireResponsesInstructions ||
                (disableImageGenerationAvailable &&
                  disableImageGeneration)) && (
                <span className="text-xs text-muted-foreground">
                  {t("providerAdvanced.compatibilityConfigEnabled", {
                    defaultValue: "已启用",
                  })}
                </span>
              )}
              {isCompatibilityConfigOpen ? (
                <ChevronDown className="h-4 w-4 text-muted-foreground" />
              ) : (
                <ChevronRight className="h-4 w-4 text-muted-foreground" />
              )}
            </div>
          </button>
          <div
            id="provider-compatibility-config"
            className={cn(
              "overflow-hidden transition-all duration-200",
              isCompatibilityConfigOpen
                ? "max-h-[560px] opacity-100"
                : "max-h-0 opacity-0",
            )}
          >
            <div className="border-t border-border/50 p-4 space-y-4">
              <div className="flex items-center justify-between gap-4">
                <div className="space-y-1">
                  <Label
                    htmlFor="omit-max-output-tokens"
                    className="font-medium"
                  >
                    {t("providerAdvanced.omitMaxOutputTokens", {
                      defaultValue: "不发送 max_output_tokens",
                    })}
                  </Label>
                  <p className="text-sm text-muted-foreground">
                    {t("providerAdvanced.omitMaxOutputTokensDesc", {
                      defaultValue:
                        "仅当 OpenAI Responses 兼容上游返回 unsupported parameter: max_output_tokens 时启用。启用后不会发送输出长度上限，长回答或长代码生成可能提前停止或变短。",
                    })}
                  </p>
                  {!omitMaxOutputTokensAvailable && (
                    <p className="text-xs text-muted-foreground">
                      {t("providerAdvanced.omitMaxOutputTokensUnavailable", {
                        defaultValue:
                          "当前 provider 格式不是 OpenAI Responses，此开关保持现有值但不可编辑。",
                      })}
                    </p>
                  )}
                </div>
                <Switch
                  id="omit-max-output-tokens"
                  checked={omitMaxOutputTokens}
                  onCheckedChange={onOmitMaxOutputTokensChange}
                  disabled={!omitMaxOutputTokensAvailable}
                />
              </div>

              {disableImageGenerationAvailable && (
                <div className="flex items-center justify-between gap-4">
                  <div className="space-y-1">
                    <Label
                      htmlFor="disable-image-generation"
                      className="font-medium"
                    >
                      {t("providerAdvanced.disableImageGeneration", {
                        defaultValue: "当前服务商按文本模式发送图片",
                      })}
                    </Label>
                    <p className="text-sm text-muted-foreground">
                      {t("providerAdvanced.disableImageGenerationDesc", {
                        defaultValue:
                          "仅对当前服务商生效。启用后，本地代理会把请求中的图片块替换为文本标记，避免上游账号组未开通 image generation 时反复 403。",
                      })}
                    </p>
                  </div>
                  <Switch
                    id="disable-image-generation"
                    checked={disableImageGeneration}
                    onCheckedChange={onDisableImageGenerationChange}
                  />
                </div>
              )}

              <div className="flex items-center justify-between gap-4">
                <div className="space-y-1">
                  <Label
                    htmlFor="require-responses-instructions"
                    className="font-medium"
                  >
                    {t("providerAdvanced.requireResponsesInstructions", {
                      defaultValue: "发送空白 instructions 字段",
                    })}
                  </Label>
                  <p className="text-sm text-muted-foreground">
                    {t("providerAdvanced.requireResponsesInstructionsDesc", {
                      defaultValue:
                        "仅当 OpenAI Responses 兼容上游在缺少 instructions 时返回 Instructions are required 时启用。启用后只补单个空格，不注入任何提示词，避免改变请求词意或回答质量。",
                    })}
                  </p>
                  {!omitMaxOutputTokensAvailable && (
                    <p className="text-xs text-muted-foreground">
                      {t(
                        "providerAdvanced.requireResponsesInstructionsUnavailable",
                        {
                          defaultValue:
                            "当前 provider 格式不是 OpenAI Responses，此开关保持现有值但不可编辑。",
                        },
                      )}
                    </p>
                  )}
                </div>
                <Switch
                  id="require-responses-instructions"
                  checked={requireResponsesInstructions}
                  onCheckedChange={onRequireResponsesInstructionsChange}
                  disabled={!omitMaxOutputTokensAvailable}
                />
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="rounded-lg border border-border/50 bg-muted/20">
        <button
          type="button"
          className="flex w-full items-center justify-between p-4 hover:bg-muted/30 transition-colors"
          onClick={() => setIsTestConfigOpen(!isTestConfigOpen)}
        >
          <div className="flex items-center gap-3">
            <FlaskConical className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">
              {t("providerAdvanced.testConfig", {
                defaultValue: "模型测试配置",
              })}
            </span>
          </div>
          <div className="flex items-center gap-3">
            <div
              className="flex items-center gap-2"
              onClick={(e) => e.stopPropagation()}
            >
              <Label
                htmlFor="test-config-enabled"
                className="text-sm text-muted-foreground"
              >
                {t("providerAdvanced.useCustomConfig", {
                  defaultValue: "使用单独配置",
                })}
              </Label>
              <Switch
                id="test-config-enabled"
                checked={testConfig.enabled}
                onCheckedChange={(checked) => {
                  onTestConfigChange({ ...testConfig, enabled: checked });
                  if (checked) setIsTestConfigOpen(true);
                }}
              />
            </div>
            {isTestConfigOpen ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            )}
          </div>
        </button>
        <div
          className={cn(
            "overflow-hidden transition-all duration-200",
            isTestConfigOpen
              ? "max-h-[500px] opacity-100"
              : "max-h-0 opacity-0",
          )}
        >
          <div className="border-t border-border/50 p-4 space-y-4">
            <p className="text-sm text-muted-foreground">
              {t("providerAdvanced.testConfigDesc", {
                defaultValue:
                  "为此供应商配置单独的模型测试参数，不启用时使用全局配置。",
              })}
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="test-model">
                  {t("providerAdvanced.testModel", {
                    defaultValue: "测试模型",
                  })}
                </Label>
                <Input
                  id="test-model"
                  value={testConfig.testModel || ""}
                  onChange={(e) =>
                    onTestConfigChange({
                      ...testConfig,
                      testModel: e.target.value || undefined,
                    })
                  }
                  placeholder={t("providerAdvanced.testModelPlaceholder", {
                    defaultValue: "留空使用全局配置",
                  })}
                  disabled={!testConfig.enabled}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="test-timeout">
                  {t("providerAdvanced.timeoutSecs", {
                    defaultValue: "超时时间（秒）",
                  })}
                </Label>
                <Input
                  id="test-timeout"
                  type="number"
                  min={1}
                  max={300}
                  value={testConfig.timeoutSecs || ""}
                  onChange={(e) =>
                    onTestConfigChange({
                      ...testConfig,
                      timeoutSecs: e.target.value
                        ? parseInt(e.target.value, 10)
                        : undefined,
                    })
                  }
                  placeholder="45"
                  disabled={!testConfig.enabled}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="test-prompt">
                  {t("providerAdvanced.testPrompt", {
                    defaultValue: "测试提示词",
                  })}
                </Label>
                <Input
                  id="test-prompt"
                  value={testConfig.testPrompt || ""}
                  onChange={(e) =>
                    onTestConfigChange({
                      ...testConfig,
                      testPrompt: e.target.value || undefined,
                    })
                  }
                  placeholder="Who are you?"
                  disabled={!testConfig.enabled}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="degraded-threshold">
                  {t("providerAdvanced.degradedThreshold", {
                    defaultValue: "降级阈值（毫秒）",
                  })}
                </Label>
                <Input
                  id="degraded-threshold"
                  type="number"
                  min={100}
                  max={60000}
                  value={testConfig.degradedThresholdMs || ""}
                  onChange={(e) =>
                    onTestConfigChange({
                      ...testConfig,
                      degradedThresholdMs: e.target.value
                        ? parseInt(e.target.value, 10)
                        : undefined,
                    })
                  }
                  placeholder="6000"
                  disabled={!testConfig.enabled}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="max-retries">
                  {t("providerAdvanced.maxRetries", {
                    defaultValue: "最大重试次数",
                  })}
                </Label>
                <Input
                  id="max-retries"
                  type="number"
                  min={0}
                  max={10}
                  value={testConfig.maxRetries ?? ""}
                  onChange={(e) =>
                    onTestConfigChange({
                      ...testConfig,
                      maxRetries: e.target.value
                        ? parseInt(e.target.value, 10)
                        : undefined,
                    })
                  }
                  placeholder="2"
                  disabled={!testConfig.enabled}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 计费配置 */}
      <div className="rounded-lg border border-border/50 bg-muted/20">
        <button
          type="button"
          className="flex w-full items-center justify-between p-4 hover:bg-muted/30 transition-colors"
          onClick={() => setIsPricingConfigOpen(!isPricingConfigOpen)}
        >
          <div className="flex items-center gap-3">
            <Coins className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">
              {t("providerAdvanced.pricingConfig", {
                defaultValue: "计费配置",
              })}
            </span>
          </div>
          <div className="flex items-center gap-3">
            <div
              className="flex items-center gap-2"
              onClick={(e) => e.stopPropagation()}
            >
              <Label
                htmlFor="pricing-config-enabled"
                className="text-sm text-muted-foreground"
              >
                {t("providerAdvanced.useCustomPricing", {
                  defaultValue: "使用单独配置",
                })}
              </Label>
              <Switch
                id="pricing-config-enabled"
                checked={pricingConfig.enabled}
                onCheckedChange={(checked) => {
                  onPricingConfigChange({ ...pricingConfig, enabled: checked });
                  if (checked) setIsPricingConfigOpen(true);
                }}
              />
            </div>
            {isPricingConfigOpen ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            )}
          </div>
        </button>
        <div
          className={cn(
            "overflow-hidden transition-all duration-200",
            isPricingConfigOpen
              ? "max-h-[500px] opacity-100"
              : "max-h-0 opacity-0",
          )}
        >
          <div className="border-t border-border/50 p-4 space-y-4">
            <p className="text-sm text-muted-foreground">
              {t("providerAdvanced.pricingConfigDesc", {
                defaultValue:
                  "为此供应商配置单独的计费参数，不启用时使用全局默认配置。",
              })}
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="cost-multiplier">
                  {t("providerAdvanced.costMultiplier", {
                    defaultValue: "成本倍率",
                  })}
                </Label>
                <Input
                  id="cost-multiplier"
                  type="number"
                  step="0.01"
                  inputMode="decimal"
                  value={pricingConfig.costMultiplier || ""}
                  onChange={(e) =>
                    onPricingConfigChange({
                      ...pricingConfig,
                      costMultiplier: e.target.value || undefined,
                    })
                  }
                  placeholder={t("providerAdvanced.costMultiplierPlaceholder", {
                    defaultValue: "留空使用全局默认（1）",
                  })}
                  disabled={!pricingConfig.enabled}
                />
                <p className="text-xs text-muted-foreground">
                  {t("providerAdvanced.costMultiplierHint", {
                    defaultValue: "实际成本 = 基础成本 × 倍率，支持小数如 1.5",
                  })}
                </p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="pricing-model-source">
                  {t("providerAdvanced.pricingModelSourceLabel", {
                    defaultValue: "计费模式",
                  })}
                </Label>
                <Select
                  value={pricingConfig.pricingModelSource}
                  onValueChange={(value) =>
                    onPricingConfigChange({
                      ...pricingConfig,
                      pricingModelSource: value as PricingModelSourceOption,
                    })
                  }
                  disabled={!pricingConfig.enabled}
                >
                  <SelectTrigger id="pricing-model-source">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="inherit">
                      {t("providerAdvanced.pricingModelSourceInherit", {
                        defaultValue: "继承全局默认",
                      })}
                    </SelectItem>
                    <SelectItem value="request">
                      {t("providerAdvanced.pricingModelSourceRequest", {
                        defaultValue: "请求模型",
                      })}
                    </SelectItem>
                    <SelectItem value="response">
                      {t("providerAdvanced.pricingModelSourceResponse", {
                        defaultValue: "返回模型",
                      })}
                    </SelectItem>
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  {t("providerAdvanced.pricingModelSourceHint", {
                    defaultValue: "选择按请求模型还是返回模型进行定价匹配",
                  })}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
